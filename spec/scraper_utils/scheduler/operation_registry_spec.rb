# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationRegistry do
  let(:response_queue) { Thread::Queue.new }
  let(:registry) { described_class.new }
  let(:authority1) { :authority1 }
  let(:authority2) { :authority2 }
  let(:fiber1) { Fiber.new do
    :fiber1
  ensure
    # required for operation to be removed from registry
    registry.deregister
  end }
  let(:fiber2) { Fiber.new do
    :fiber2
  ensure
    # required for operation to be removed from registry
    registry.deregister
  end }

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
  end

  describe "#initialize" do
    it "creates empty operations and fiber_ids hashes" do
      expect(registry.instance_variable_get(:@operations)).to eq({})
      expect(registry.instance_variable_get(:@fiber_ids)).to eq({})
    end
  end

  describe "#register and #deregister" do
    it "registers and deregisters operations" do
      fiber = Fiber.new do
        # Deregister the operation
        registry.deregister
        :the_end
      end

      # Register the operation
      registry.instance_variable_set(:@response_queue, response_queue)
      registry.register(fiber, authority1)

      # Verify it was registered
      operations = registry.instance_variable_get(:@operations)
      fiber_ids = registry.instance_variable_get(:@fiber_ids)

      expect(operations[authority1]).to be_a(ScraperUtils::Scheduler::OperationWorker)
      expect(fiber_ids[fiber.object_id]).to eq(operations[authority1])

      # Allow fiber to deregister itself
      fiber.resume

      # Verify it was deregistered
      expect(registry.instance_variable_get(:@operations)).to be_empty
      expect(registry.instance_variable_get(:@fiber_ids)).to be_empty
    end
  end

  describe "#shutdown, #empty? and #size" do
    it "manages the registry state" do
      expect(registry.empty?).to be true
      expect(registry.size).to eq(0)
      fiber1_ran = false
      fiber2_ran = false
      fiber1 = Fiber.new do
        fiber1_ran = true
      ensure
        # required for operation to be removed from registry
        registry.deregister
      end
      fiber2 = Fiber.new do
        fiber2_ran = true
      ensure
        # required for operation to be removed from registry
        registry.deregister
      end
      registry.register(fiber1, :authority1)
      registry.register(fiber2, :authority2)

      expect(registry.empty?).to be false
      expect(registry.size).to eq(2)
      expect(fiber1_ran).to be false
      expect(fiber2_ran).to be false

      # Shut down
      registry.shutdown

      expect(fiber1_ran).to be true
      expect(fiber2_ran).to be true
      expect(registry.empty?).to be true
      expect(registry.size).to eq(0)
    end
  end
end
