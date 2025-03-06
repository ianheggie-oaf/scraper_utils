# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "FiberScheduler and ThreadScheduler Integration" do
  before do
    ScraperUtils::FiberScheduler.reset!
  end

  after do
    ScraperUtils::FiberScheduler.thread_scheduler&.shutdown
  end

  describe "queue_async_command integration" do
    let(:test_url1) { "http://example.com/test1" }
    let(:test_url2) { "http://example.com/test2" }
    let(:test_url3) { "http://example.com/error" }
    
    before do
      # Stub the HTTP requests with different response times
      stub_request(:get, test_url1)
        .to_return(
          status: 200, 
          body: "<html><body>Test Page 1</body></html>", 
          headers: { 'Content-Type' => 'text/html' }
        )
        
      stub_request(:get, test_url2)
        .to_return(
          status: 200, 
          body: "<html><body>Test Page 2</body></html>", 
          headers: { 'Content-Type' => 'text/html' }
        )
        
      stub_request(:get, test_url3)
        .to_return(
          status: 500, 
          body: "Internal Server Error",
          headers: { 'Content-Type' => 'text/html' }
        )
    end
    
    it "executes commands in parallel with proper response handling" do
      results = {}
      errors = {}
      
      # Create one Mechanize client per authority (best practice)
      client1 = Mechanize.new
      client2 = Mechanize.new
      
      # Register two operations with async commands
      ScraperUtils::FiberScheduler.register_operation("authority1") do
        begin
          page = ScraperUtils::FiberScheduler.queue_async_command(client1, :get, [test_url1])
          results["authority1"] = page.body
        rescue StandardError => e
          errors["authority1"] = e
        end
      end
      
      ScraperUtils::FiberScheduler.register_operation("authority2") do
        begin
          page = ScraperUtils::FiberScheduler.queue_async_command(client2, :get, [test_url2])
          results["authority2"] = page.body
        rescue StandardError => e
          errors["authority2"] = e
        end
      end
      
      # Run all operations
      ScraperUtils::FiberScheduler.run_all
      
      # Check results
      expect(results["authority1"]).to include("Test Page 1")
      expect(results["authority2"]).to include("Test Page 2")
      expect(errors).to be_empty
    end
    
    it "handles errors properly" do
      results = {}
      
      # Create Mechanize client
      client = Mechanize.new
      
      # Register operation with error-producing command
      ScraperUtils::FiberScheduler.register_operation("error_authority") do
        begin
          ScraperUtils::FiberScheduler.queue_async_command(client, :get, [test_url3])
          :success
        rescue StandardError => e
          results["error"] = e.class.name
          :error
        end
      end
      
      # Run the operation
      ScraperUtils::FiberScheduler.run_all
      
      # Check error handling
      expect(results["error"]).to include("Mechanize::ResponseCode")
    end
    
    it "interleaves operations with delays" do
      sequence = []
      
      # Register operations with delays
      ScraperUtils::FiberScheduler.register_operation("auth1") do
        sequence << "auth1 start"
        ScraperUtils::FiberScheduler.delay(0.05)
        sequence << "auth1 after delay"
        
        # Make async command
        client = Mechanize.new
        ScraperUtils::FiberScheduler.queue_async_command(client, :get, [test_url1])
        
        sequence << "auth1 after command"
      end
      
      ScraperUtils::FiberScheduler.register_operation("auth2") do
        sequence << "auth2 start"
        ScraperUtils::FiberScheduler.delay(0.03)
        sequence << "auth2 after delay"
        
        # Make async command
        client = Mechanize.new
        ScraperUtils::FiberScheduler.queue_async_command(client, :get, [test_url2])
        
        sequence << "auth2 after command"
      end
      
      # Run operations
      ScraperUtils::FiberScheduler.run_all
      
      # Verify proper interleaving
      expected_sequence = [
        "auth1 start", 
        "auth2 start", 
        "auth2 after delay", 
        "auth1 after delay", 
        "auth2 after command", 
        "auth1 after command"
      ]
      
      expect(sequence).to eq(expected_sequence)
    end
  end
end
