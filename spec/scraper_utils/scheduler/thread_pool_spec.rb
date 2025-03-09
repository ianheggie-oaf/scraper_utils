# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadPool do
  let(:executor) { described_class.new(3) } # Use 3 threads for testing

  after do
    executor.shutdown
  end

  describe "#submit_request and #get_response" do
    let(:test_url) { "http://example.com/test" }
    let(:test_url2) { "http://example.com/test2" }
    let(:test_form_url) { "http://example.com/form" }
    let(:mechanize_client) { Mechanize.new }
    let(:authority) { :test_authority }

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

    it "executes a simple sleep and returns the response" do
      command = ScraperUtils::Scheduler::ProcessRequest.new(authority, Kernel, :sleep, [0.001])

      # Queue the request
      executor.submit_request(command)
      response = nil
      # Wait up to 5 seconds for the request to complete
      500.times do
        response = executor.get_response
        break if response

        sleep 0.01
      end

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response&.authority).to eq(authority)
      expect(response&.result).to be_a(Integer)
      expect(response&.error).to be_nil
      expect(response&.time_taken).to be > 0
      expect(response&.success?).to be true
      expect(response&.result).to be 0
    end

    it "executes a GET request and returns the response" do
      command = ScraperUtils::Scheduler::ProcessRequest.new(authority, mechanize_client, :get, [test_url])

      # Queue the request
      executor.submit_request(command)

      response = executor.get_response(false)

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response&.authority).to eq(authority)
      expect(response&.result).to be_a(Mechanize::Page)
      expect(response&.result.body).to include("Test Page")
      expect(response&.error).to be_nil
      expect(response&.time_taken).to be > 0
      expect(response&.success?).to be true
    end

    it "handles errors and returns them in the response" do
      command = ScraperUtils::Scheduler::ProcessRequest.new(authority, mechanize_client, :get, ["http://example.com/error"])

      # Queue the request
      executor.submit_request(command)

      # Check the response
      response = executor.get_response(false)
      expect(response&.authority).to eq(authority)
      expect(response&.result).to be_nil
      expect(response&.error).to be_a(Exception)
      expect(response&.time_taken).to be > 0
      expect(response&.success?).to be false
    end

    it "Returns nil when non_block is true and no responses are available" do
      expect(executor.get_response).to be nil
    end

    it "executes multiple requests in parallel" do
      authorities = [1001, 1002, 1003]

      start_time = Time.now

      # Queue requests
      authorities.each_with_index do |id, i|
        command = ScraperUtils::Scheduler::ProcessRequest.new(
          id,
          Kernel, # Each request gets its own Mechanize instance
          :sleep,
          [0.01]
        )

        executor.submit_request(command)
      end

      responses = executor.shutdown

      total_time = Time.now - start_time

      # Check that all requests were processed
      expect(responses).to be_an(Array)
      expect(responses.size).to eq(3)

      # Check that each response succeeded
      responses.each do |response|
        expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(authorities).to include(response.authority)
        expect(response.result).to be_a(Integer)
        expect(response.error).to be_nil
        expect(response.time_taken).to be > 0
        expect(response.success?).to be true
      end

      # The total time should be less than the sum of individual request times
      individual_times_sum = responses.sum(&:time_taken)

      expect(total_time).to be < individual_times_sum
    end

    it "can submit_request delay operations" do
      test_object = Object.new
      def test_object.sleep_test(seconds)
        sleep(seconds)
        "Slept for #{seconds} seconds"
      end

      start_time = Time.now
      delay_till = start_time + 0.1

      # Create commands that will sleep
      command1 = ScraperUtils::Scheduler::DelayRequest.new(:sleep1, delay_till)
      command2 = ScraperUtils::Scheduler::DelayRequest.new(:sleep2, delay_till)
      command3 = ScraperUtils::Scheduler::DelayRequest.new(:sleep3, delay_till)

      # Queue all commands
      executor.submit_request(command1)
      executor.submit_request(command2)
      executor.submit_request(command3)

      # Process responses
      responses = [
        executor.get_response(false),
        executor.get_response(false),
        executor.get_response(false)
      ]

      # Check total time - should be less than sum of sleep times if truly parallel
      total_time = Time.now - start_time
      expect(total_time).to be < 0.3  # Less than 3 sequential 0.1s sleeps

      responses.each do |response|
        expect(response.success?).to be true
        expect(response.result).to be 0
      end
    end
  end

  describe "#shutdown" do
    it "gracefully shuts down the executor when empty" do
      results = nil
      # This is mostly to ensure the shutdown method doesn't raise errors
      expect { results = executor.shutdown }.not_to raise_error

      # Verify it returns remaining responses
      expect(results).to be_an(Array)
      expect(results).to be_empty
    end

    it "gracefully shuts down the executor, waiting for responses" do
      # This is mostly to ensure the shutdown method doesn't raise errors
      results = nil
      command1 = ScraperUtils::Scheduler::ProcessRequest.new("sleep1", Kernel, :sleep, [0.1])
      executor.submit_request(command1)
      expect { results = executor.shutdown }.not_to raise_error

      expect(results).to be_an(Array)
      expect(results&.size).to eq(1)
    end
  end
end
