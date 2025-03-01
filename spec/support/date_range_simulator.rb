# frozen_string_literal: true

require 'date'
require 'terminal-table'

module DateRangeSimulator
  # Runs a simulation on the date range algorithm
  # @param days [Integer] Number of days to cover
  # @param everytime [Integer] Days to always include
  # @param max_period [Integer] Maximum period between checks
  # @param simulation_days [Integer, nil] Length of simulation in days, default: days * 2
  # @return [Hash] Statistics from the simulation
  def self.run_simulation(utils, days:, everytime:, max_period:)
    # Track which days are checked
    checked_days = {}
    days_checked_per_day = []
    today = Date.today
    current_start_date =  today - days + 1

    puts "DEBUG Simulating days: #{days} [#{current_start_date} .. #{today}], everytime: #{everytime}, max_period: #{max_period} (starting #{days} earlier)"

    simulation_days = days * 2
    # This is a hash of date to date last checked
    last_checked = {}

    # Run simulation for specified days
    max_streak = 0
    simulation_days.times do |i|
      simulation_date = today - simulation_days + i + 1

      # Calculate ranges for this day
      ranges = utils.calculate_date_ranges(
        days: days,
        everytime: everytime,
        max_period: max_period,
        today: simulation_date
      )
      puts "DEBUG #{simulation_date - days + 1} .. #{simulation_date} searches: #{ranges.map{|a,b, c| "[#{a} .. #{b} = #{(b-a).to_i + 1}; #{c}]"}.join(', ')}"

      # Track which days were checked
      days_checked_today = 0

      ranges.each do |range|
        start_date, end_date = range
        (start_date..end_date).each do |date|
          checked_days[date] ||= 0
          checked_days[date] += 1
          if last_checked[date]
            streak = (simulation_date - last_checked[date]).to_i
            if streak > max_streak && date >= current_start_date
              if streak > max_period
                raise "DEBUG: streak of #{streak} found on #{simulation_date}: #{date} was last checked #{last_checked[date]}"
              end
              max_streak = streak
            end
          end
          last_checked[date] = simulation_date
          days_checked_today += 1
        end
      end
      days_checked_per_day << days_checked_today
    end
    # check current range
    (current_start_date - 1 .. today).each do |date|
      raise "#{date} has never been checked!" unless last_checked[date]

      streak = (today - last_checked[date]).to_i
      if streak > max_streak
        if streak > max_period
          raise "DEBUG: streak of #{streak} found today (#{today}): #{date} was last checked #{last_checked[date]}"
        end
        max_streak = streak
      end
    end

    # Calculate statistics
    unchecked_dates = []

    (current_start_date..today).each do |date|
      if checked_days[date].nil?
        unchecked_dates << date
      end
    end

    # Build a stats table
    coverage = ((checked_days.keys.count.to_f / days) * 100).round(1)

    # Create result hash
    stats = {
      days: days,
      everytime: everytime,
      max_period: max_period,
      coverage_percentage: coverage,
      unchecked_days: unchecked_dates.count,
      max_unchecked_streak: max_streak,
      avg_checked_per_day: (days_checked_per_day.sum.to_f / days_checked_per_day.size).round(1),
      min_checked_per_day: days_checked_per_day.min,
      max_checked_per_day: days_checked_per_day.max
    }

    # Generate an ASCII table
    table = Terminal::Table.new do |t|
      t.title = "Date Range Simulation Results"
      t.headings = %w[Metric Value Comments]

      t.add_row ["Days", stats[:days], ""]
      t.add_row ["Everytime", stats[:everytime], ""]
      t.add_row ["Max Period", stats[:max_period], ""]
      t.add_row ["Coverage", "#{stats[:coverage_percentage]}%", ""]
      t.add_row ["Unchecked Days", stats[:unchecked_days], "Should be zero, was: #{unchecked_dates.inspect}"]
      t.add_row ["Max Unchecked Streak", stats[:max_unchecked_streak], "Should be <= #{max_period}"]
      t.add_row ["Avg Checked Per Day", stats[:avg_checked_per_day], "Should be approx #{(days / max_period).round(1)}"]
      t.add_row ["Min Checked Per Day", stats[:min_checked_per_day], ""]
      t.add_row ["Max Checked Per Day", stats[:max_checked_per_day], ""]
    end

    stats.merge({table: table})
  end
end
