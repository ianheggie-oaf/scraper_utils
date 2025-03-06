# frozen_string_literal: true

require_relative '../spec_helper'
require 'mechanize'

RSpec.describe ScraperUtils::ThreadScheduler do
  let(:executor) { described_class.new(3) } # Use 3 threads for testing
  
  after do
    executor.shutdown
  end
  
  describe "#queue_request and #process_responses" do
    let(:test_url) { "http://example.com/test" }
    let(:test_url2) { "http://example.com/test2" }
    let(:test_form_url) { "http://example.com/form" }
    let(:mechanize_client) { Mechanize.new }
    
    before do
      # Stub HTTP requests
      stub_request(:get, test_url)
        .to_return(status: 200, body: "<html><body>Test Page</body></html>", 
                   headers: { 'Content-Type' => 'text/html' })
                   
      stub_request(:get, test_url2)
        .to_return(status: 200, body: "<html><body>Test Page 2</body></html>", 
                   headers: { 'Content-Type' => 'text/html' })
                   
      stub_request(:get, "http://example.com/error")
        .to_return(status: 500, body: "Internal Server Error")
        
      stub_request(:post, test_form_url)
        .with(body: {"field" => "value"})
        .to_return(status: 200, body: "<html><body>Form Submitted</body></html>",
                   headers: { 'Content-Type' => 'text/html' })
    end
    
    it "executes a GET request and stores the result in fiber data" do
      fiber = Fiber.new { Fiber.yield }
      
      command = {
        client: mechanize_client,
        method: :get,
        args: [test_url]
      }
      
      # Queue the request
      executor.queue_request(fiber, command)
      
      # Wait a bit for the request to complete
      sleep 0.1
      
      # Process responses
      processed = executor.process_responses
      
      # Check that our fiber was processed
      expect(processed).to be_an(Array)
      expect(processed.size).to eq(1)
      expect(processed[0][0]).to eq(fiber)
      
      # Check the fiber data
      fiber_data = fiber.instance_variable_get(:@data)
      expect(fiber_data[:last_response]).to be_a(Mechanize::Page)
      expect(fiber_data[:last_response].body).to include("Test Page")
      expect(fiber_data[:last_error]).to be_nil
      expect(fiber_data[:last_request_time]).to be_a(Float)
      expect(fiber_data[:last_request_time]).to be > 0
      expect(fiber_data[:response_ready]).to be true
    end
    
    it "handles errors and stores them in fiber data" do
      fiber = Fiber.new { Fiber.yield }
      
      command = {
        client: mechanize_client,
        method: :get,
        args: ["http://example.com/error"]
      }
      
      # Queue the request
      executor.queue_request(fiber, command)
      
      # Wait a bit for the request to complete
      sleep 0.1
      
      # Process responses
      executor.process_responses
      
      # Check the fiber data
      fiber_data = fiber.instance_variable_get(:@data)
      expect(fiber_data[:last_response]).to be_nil
      expect(fiber_data[:last_error]).to be_a(Exception)
      expect(fiber_data[:last_request_time]).to be_a(Float)
      expect(fiber_data[:last_request_time]).to be > 0
      expect(fiber_data[:response_ready]).to be true
    end
    
    it "handles timeout for process_responses" do
      # No requests queued, so should time out
      result = executor.process_responses(0.1)
      expect(result).to be_nil
    end
    
    it "executes multiple requests in parallel" do
      fibers = 3.times.map do |i|
        Fiber.new { Fiber.yield }
      end
      
      start_time = Time.now
      
      # Queue requests for all fibers
      fibers.each_with_index do |fiber, i|
        command = {
          client: Mechanize.new, # Each fiber gets its own Mechanize instance
          method: :get,
          args: [i.even? ? test_url : test_url2]
        }
        
        executor.queue_request(fiber, command)
      end
      
      # Wait for all requests to complete
      sleep 0.5
      
      # Process all responses
      processed = executor.process_responses
      
      total_time = Time.now - start_time
      
      # Check that all fibers were processed
      expect(processed).to be_an(Array)
      expect(processed.size).to eq(3)
      
      # Check that each request succeeded
      fibers.each do |fiber|
        fiber_data = fiber.instance_variable_get(:@data)
        expect(fiber_data[:last_response]).to be_a(Mechanize::Page)
        expect(fiber_data[:last_error]).to be_nil
        expect(fiber_data[:last_request_time]).to be_a(Float)
        expect(fiber_data[:last_request_time]).to be > 0
        expect(fiber_data[:response_ready]).to be true
      end
      
      # The total time should be less than the sum of individual request times
      individual_times_sum = fibers.sum do |fiber|
        fiber.instance_variable_get(:@data)[:last_request_time]
      end
      
      expect(total_time).to be < individual_times_sum
    end
  end
  
  describe "#responses_pending?" do
    it "returns true when responses are pending" do
      fiber = Fiber.new { Fiber.yield }
      
      # Queue a dummy request that will never complete
      allow_any_instance_of(Mechanize).to receive(:get).and_return(nil)
      
      # Add response directly to queue
      executor.instance_variable_get(:@response_queue) << [fiber, "test", nil, 0.1]
      
      expect(executor.responses_pending?).to be true
    end
    
    it "returns false when no responses are pending" do
      # Empty the queue
      queue = executor.instance_variable_get(:@response_queue)
      queue.clear if queue.respond_to?(:clear)
      
      expect(executor.responses_pending?).to be false
    end
  end

  describe "#shutdown" do
    it "gracefully shuts down the executor" do
      # This is mostly to ensure the shutdown method doesn't raise errors
      expect { executor.shutdown }.not_to raise_error
    end
  end
end
