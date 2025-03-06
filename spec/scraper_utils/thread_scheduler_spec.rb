# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::ThreadScheduler do
  let(:executor) { described_class.new(3) } # Use 3 threads for testing

  after do
    executor.shutdown
  end

  describe "#enqueue_command and #next_response" do
    let(:test_url) { "http://example.com/test" }
    let(:test_url2) { "http://example.com/test2" }
    let(:test_form_url) { "http://example.com/form" }
    let(:mechanize_client) { Mechanize.new }
    let(:external_id) { 12345 }

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
      command = ScraperUtils::AsyncCommand.new(external_id, Kernel, :sleep, [0.001])

      # Queue the request
      executor.enqueue_command(command)

      # Wait a bit for the request to complete
      50.times do
        break if executor.responses_pending?

        sleep 0.1
      end

      # Check if responses are pending
      expect(executor.responses_pending?).to be true

      # Process response
      response = executor.next_response

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::AsyncResponse)
      expect(response.external_id).to eq(external_id)
      expect(response.result).to be_a(Integer)
      expect(response.error).to be_nil
      expect(response.time_taken).to be > 0
      expect(response.success?).to be true
      expect(response.result).to be 0
    end

    it "executes a GET request and returns the response" do
      command = ScraperUtils::AsyncCommand.new(external_id, mechanize_client, :get, [test_url])

      # Queue the request
      executor.enqueue_command(command)

      # Wait a bit for the request to complete
      sleep 0.1

      # Check if responses are pending
      expect(executor.responses_pending?).to be true

      # Process response
      response = executor.next_response

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::AsyncResponse)
      expect(response.external_id).to eq(external_id)
      expect(response.result).to be_a(Mechanize::Page)
      expect(response.result.body).to include("Test Page")
      expect(response.error).to be_nil
      expect(response.time_taken).to be > 0
      expect(response.success?).to be true
    end

    it "handles errors and returns them in the response" do
      command = ScraperUtils::AsyncCommand.new(external_id, mechanize_client, :get, ["http://example.com/error"])

      # Queue the request
      executor.enqueue_command(command)

      # Wait a bit for the request to complete
      sleep 0.1

      # Check the response
      response = executor.next_response
      expect(response.external_id).to eq(external_id)
      expect(response.result).to be_nil
      expect(response.error).to be_a(Exception)
      expect(response.time_taken).to be > 0
      expect(response.success?).to be false
    end

    it "Raises ThreadError when non_block is true and no responses are available" do
      expect { executor.next_response(true) }.to raise_error(ThreadError)
    end

    it "executes multiple requests in parallel" do
      external_ids = [1001, 1002, 1003]

      start_time = Time.now

      # Queue requests
      external_ids.each_with_index do |id, i|
        command = ScraperUtils::AsyncCommand.new(
          id,
          Kernel, # Each request gets its own Mechanize instance
          :sleep,
          [0.01]
        )

        executor.enqueue_command(command)
      end

      responses = executor.shutdown

      total_time = Time.now - start_time

      # Check that all requests were processed
      expect(responses).to be_an(Array)
      expect(responses.size).to eq(3)

      # Check that each response succeeded
      responses.each do |response|
        expect(response).to be_a(ScraperUtils::AsyncResponse)
        expect(external_ids).to include(response.external_id)
        expect(response.result).to be_a(Integer)
        expect(response.error).to be_nil
        expect(response.time_taken).to be > 0
        expect(response.success?).to be true
      end

      # The total time should be less than the sum of individual request times
      individual_times_sum = responses.sum(&:time_taken)

      expect(total_time).to be < individual_times_sum
    end

    it "can enqueue_command non-network operations" do
      test_object = Object.new
      def test_object.sleep_test(seconds)
        sleep(seconds)
        "Slept for #{seconds} seconds"
      end

      start_time = Time.now

      # Create commands that will sleep
      command1 = ScraperUtils::AsyncCommand.new("sleep1", test_object, :sleep_test, [0.1])
      command2 = ScraperUtils::AsyncCommand.new("sleep2", test_object, :sleep_test, [0.1])
      command3 = ScraperUtils::AsyncCommand.new("sleep3", test_object, :sleep_test, [0.1])

      # Queue all commands
      executor.enqueue_command(command1)
      executor.enqueue_command(command2)
      executor.enqueue_command(command3)

      # Process responses
      responses = [
        executor.next_response,
        executor.next_response,
        executor.next_response
      ]

      # Check total time - should be less than sum of sleep times if truly parallel
      total_time = Time.now - start_time
      expect(total_time).to be < 0.3  # Less than 3 sequential 0.1s sleeps

      responses.each do |response|
        expect(response.success?).to be true
        expect(response.result).to eq("Slept for 0.1 seconds")
      end
    end
  end

  describe "#responses_pending?" do
    it "returns true when responses are pending" do
      # Add response directly to queue
      executor.instance_variable_get(:@response_queue) <<
        ScraperUtils::AsyncResponse.new(1234, "test")

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
      command1 = ScraperUtils::AsyncCommand.new("sleep1", Kernel, :sleep, [0.1])
      executor.enqueue_command(command1)
      expect { results = executor.shutdown }.not_to raise_error

      expect(results).to be_an(Array)
      expect(results&.size).to eq(1)
    end
  end
end
