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
    let(:fiber_id) { 12345 }
    
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
    
    it "executes a GET request and returns the response" do
      request = ScraperUtils::NetworkRequest.new(fiber_id, mechanize_client, :get, [test_url])
      
      # Queue the request
      executor.queue_request(request)
      
      # Wait a bit for the request to complete
      sleep 0.1
      
      # Process responses
      responses = executor.process_responses
      
      # Check that we got a response
      expect(responses).to be_an(Array)
      expect(responses.size).to eq(1)
      
      response = responses.first
      expect(response).to be_a(ScraperUtils::NetworkResponse)
      expect(response.fiber_id).to eq(fiber_id)
      expect(response.result).to be_a(Mechanize::Page)
      expect(response.result.body).to include("Test Page")
      expect(response.error).to be_nil
      expect(response.time_taken).to be > 0
      expect(response.success?).to be true
    end
    
    it "handles errors and returns them in the response" do
      request = ScraperUtils::NetworkRequest.new(fiber_id, mechanize_client, :get, ["http://example.com/error"])
      
      # Queue the request
      executor.queue_request(request)
      
      # Wait a bit for the request to complete
      sleep 0.1
      
      # Process responses
      responses = executor.process_responses
      
      # Check the response
      response = responses.first
      expect(response.fiber_id).to eq(fiber_id)
      expect(response.result).to be_nil
      expect(response.error).to be_a(Exception)
      expect(response.time_taken).to be > 0
      expect(response.success?).to be false
    end
    
    it "handles timeout for process_responses" do
      # No requests queued, so should time out
      result = executor.process_responses(0.1)
      expect(result).to be_empty
    end
    
    it "executes multiple requests in parallel" do
      fiber_ids = [1001, 1002, 1003]
      
      start_time = Time.now
      
      # Queue requests
      fiber_ids.each_with_index do |id, i|
        request = ScraperUtils::NetworkRequest.new(
          id, 
          Mechanize.new, # Each request gets its own Mechanize instance
          :get,
          [i.even? ? test_url : test_url2]
        )
        
        executor.queue_request(request)
      end
      
      # Wait for all requests to complete
      sleep 0.5
      
      # Process all responses
      responses = executor.process_responses
      
      total_time = Time.now - start_time
      
      # Check that all requests were processed
      expect(responses).to be_an(Array)
      expect(responses.size).to eq(3)
      
      # Check that each response succeeded
      responses.each do |response|
        expect(response).to be_a(ScraperUtils::NetworkResponse)
        expect(fiber_ids).to include(response.fiber_id)
        expect(response.result).to be_a(Mechanize::Page)
        expect(response.error).to be_nil
        expect(response.time_taken).to be > 0
        expect(response.success?).to be true
      end
      
      # The total time should be less than the sum of individual request times
      individual_times_sum = responses.sum(&:time_taken)
      
      expect(total_time).to be < individual_times_sum
    end
  end
  
  describe "#responses_pending?" do
    it "returns true when responses are pending" do
      # Add response directly to queue
      executor.instance_variable_get(:@response_queue) << 
        ScraperUtils::NetworkResponse.new(1234, "test")
      
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
