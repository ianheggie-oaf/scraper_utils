# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationRegistry do
  let(:response_queue) { Thread::Queue.new }
  let(:registry) { described_class.new }
  let(:authority1) { :authority1 }
  let(:authority2) { :authority2 }
  let(:authority3) { :authority3 }
  let(:fiber1) { Fiber.new { :fiber1 } }
  let(:fiber2) { Fiber.new { :fiber2 } }

  describe "#current_authority" do
    let(:fiber) { Fiber.current }
    let(:operation) { double("OperationWorker", fiber: fiber, authority: authority1) }

    before do
      registry.instance_variable_set(:@fiber_ids, { fiber.object_id => operation })
    end

    it "returns the authority of the current fiber" do
      expect(registry.current_authority).to eq(authority1)
    end

    it "returns nil if current fiber is not registered" do
      registry.instance_variable_set(:@fiber_ids, {})
      expect(registry.current_authority).to be_nil
    end
  end

  describe "#find" do
    let(:operation1) { double("OperationWorker", fiber: fiber1, authority: authority1) }
    let(:operation2) { double("OperationWorker", fiber: fiber2, authority: authority2) }

    before do
      registry.instance_variable_set(:@operations, {
        authority1 => operation1,
        authority2 => operation2
      })
      registry.instance_variable_set(:@fiber_ids, {
        fiber1.object_id => operation1,
        fiber2.object_id => operation2
      })
    end

    it "finds operation by authority symbol" do
      expect(registry.find(authority1)).to eq(operation1)
      expect(registry.find(authority2)).to eq(operation2)
    end

    it "finds operation by fiber ID" do
      expect(registry.find(fiber1.object_id)).to eq(operation1)
      expect(registry.find(fiber2.object_id)).to eq(operation2)
    end

    it "uses current fiber ID when no key provided" do
      allow(Fiber).to receive(:current).and_return(fiber1)
      expect(registry.find).to eq(operation1)
    end

    it "returns nil when key not found" do
      expect(registry.find(:unknown)).to be_nil
      expect(registry.find(999999)).to be_nil
    end
  end

  describe "#empty?" do
    it "returns true when no operations are registered" do
      expect(registry.empty?).to be true
    end

    it "returns false when operations are registered" do
      registry.instance_variable_set(:@operations, { authority1 => double })
      expect(registry.empty?).to be false
    end
  end

  describe "#size" do
    it "returns the number of registered operations" do
      expect(registry.size).to eq(0)

      registry.instance_variable_set(:@operations, {
        authority1 => double,
        authority2 => double
      })

      expect(registry.size).to eq(2)
    end
  end

  describe "#can_resume" do
    let(:operation1) { double("OperationWorker1", can_resume?: true, resume_at: Time.now + 1) }
    let(:operation2) { double("OperationWorker2", can_resume?: true, resume_at: Time.now) }
    let(:operation3) { double("OperationWorker3", can_resume?: false, resume_at: Time.now - 1) }

    before do
      registry.instance_variable_set(:@operations, {
        authority1 => operation1,
        authority2 => operation2,
        authority3 => operation3
      })
    end

    it "returns operations that can resume, sorted by resume_at" do
      result = registry.can_resume

      expect(result).to include(operation1, operation2)
      expect(result).not_to include(operation3)
      expect(result.first).to eq(operation2) # Earliest resume_at should be first
    end

    it "returns empty array when no operations can resume" do
      registry.instance_variable_set(:@operations, { authority1 => operation3 })

      expect(registry.can_resume).to be_empty
    end
  end

  describe "#process_thread_response" do
    let(:response) { double("ThreadResponse", authority: authority1) }
    let(:operation) { double("OperationWorker", save_thread_response: nil) }

    before do
      registry.instance_variable_set(:@operations, { authority1 => operation })
    end

    it "forwards response to matching operation" do
      registry.process_thread_response(response)

      expect(operation).to have_received(:save_thread_response).with(response)
    end

    it "does nothing when authority not found" do
      response = double("ThreadResponse", authority: :unknown)

      # Should not raise an error
      registry.process_thread_response(response)
    end
  end
end
