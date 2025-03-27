# frozen_string_literal: true

# Helper class for testing thread requests with configurable behavior
class TestThreadRequest < ScraperUtils::Scheduler::ThreadRequest
  attr_reader :executed, :delay_till

  def initialize(authority, result: nil, error: nil, delay_till: nil)
    super(authority)
    @result = result
    @error = error
    @delay_till = delay_till
    @executed = false
  end

  def execute
    @executed = true
    result = if @error
      execute_block { raise @error }
    else
      execute_block { @result || :default_result }
    end
    result.delay_till = @delay_till if result
    result
  end
end
