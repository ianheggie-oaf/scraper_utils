# frozen_string_literal: true

require 'date'
require 'terminal-table'

require_relative 'date_range_visualizer'

module DateRangeSimulator
  # Runs a simulation on the date range algorithm
  # @param utils [DateRangeUtils] The DateRangeUtils instance to use
  # @param days [Integer] Number of days to cover
  # @param everytime [Integer] Days to always include
  # @param max_period [Integer] Maximum period between checks
  # @param simulation_days [Integer, nil] Length of simulation in days, default: days * 2
  # @param visualize [Boolean] Create visualization even if no error occurs
  # @return [Hash] Statistics from the simulation
  def self.run_simulation(utils, days:, everytime:, max_period:, simulation_days: nil, visualize: false)
    # Track which days are checked
    checked_days = {}
    days_checked_per_day = []
    today = Date.today
    current_start_date = today - days + 1

    puts "DEBUG Simulating days: #{days} [#{current_start_date} .. #{today}], everytime: #{everytime}, max_period: #{max_period} (starting #{days} earlier)" if ENV['DEBUG'] == '3'

    simulation_days ||= days * 2
    start_simulation_date = today + 1 - simulation_days
    # This is a hash of date to date last checked
    last_checked = {}

    # For visualization purpose, store search ranges by date
    simulation_history = {}

    # Run simulation for specified days
    max_streak = 0
    error = nil

    simulation_days.times do |i|
      simulation_date = today - simulation_days + i + 1

      # Calculate ranges for this day
      ranges = utils.calculate_date_ranges(
        days: days,
        everytime: everytime,
        max_period: max_period,
        today: simulation_date
      )

      # Store search ranges for this date
      simulation_history[simulation_date] = []

      # Log the ranges
      puts "DEBUG #{simulation_date - days + 1} .. #{simulation_date} searches: #{ranges.map { |a, b, c| "[#{a} .. #{b} = #{(b - a).to_i + 1}; #{c}]" }.join(', ')}" if ENV['DEBUG'] == '3'

      # Track which days were checked
      days_checked_today = 0

      ranges.each do |range|
        start_date, end_date, comment = range

        # Store search range info for visualization
        simulation_history[simulation_date] << [start_date, end_date, comment]

        (start_date..end_date).each do |search_date|
          next if search_date < start_simulation_date

          checked_days[search_date] ||= 0
          checked_days[search_date] += 1
          last_checked[search_date] = simulation_date
          days_checked_today += 1 if search_date > simulation_date - days
        end
      end
      days_checked_per_day << days_checked_today if simulation_date >= current_start_date
      # Check for long streaks
      (simulation_date..today).each do |search_date|
        if last_checked[search_date]
          streak = (simulation_date - last_checked[search_date]).to_i
          if streak > max_streak && search_date >= current_start_date
            max_streak = streak
            if streak > max_period
              error_msg = "Streak of #{streak} found on #{simulation_date}: #{search_date} was last checked #{last_checked[search_date]}"
              puts "ERROR: #{error_msg}"
              error = {
                streak: streak,
                found_on: simulation_date,
                search_date: search_date,
                last_checked: last_checked[search_date],
                message: error_msg
              }
              break
            end
          end
        end
        break if error
      end
      break if error
    end

    # Only do final check if we didn't find an error yet
    unless error
      # Check if all dates are covered
      (current_start_date..today).each do |search_date|
        unless last_checked[search_date]
          error_msg = "#{search_date} has never been checked!"
          puts "ERROR: #{error_msg}"
          error = {
            streak: today + 1 - start_simulation_date,
            found_on: today,
            search_date: search_date,
            last_checked: start_simulation_date - 1,
            message: error_msg
          }
          break
        end

        streak = (today - last_checked[search_date]).to_i
        if streak > max_streak
          if streak > max_period
            error_msg = "Streak of #{streak} found today (#{today}): #{search_date} was last checked #{last_checked[search_date]}"
            puts "ERROR: #{error_msg}"
            error = {
              streak: streak,
              found_on: today,
              search_date: search_date,
              last_checked: last_checked[search_date],
              message: error_msg
            }
            break
          end
          max_streak = streak
        end
      end
    end

    # Calculate statistics
    unchecked_dates = []
    checked_dates = []

    (current_start_date..today).each do |search_date|
      if checked_days[search_date].nil?
        unchecked_dates << search_date
      else
        checked_dates << search_date
      end
    end

    # Build a stats table
    coverage = ((checked_dates.size.to_f / days) * 100).round(1)

    # Create result hash
    stats = {
      days: days,
      everytime: everytime,
      max_period: max_period,
      coverage_percentage: coverage,
      unchecked_days: unchecked_dates.count,
      max_unchecked_streak: max_streak,
      avg_checked_per_day: (days_checked_per_day.sum * 100.0 / (days * days)).round(1),
      min_checked_per_day: (days_checked_per_day.min * 100.0 / days).round(1),
      max_checked_per_day: (days_checked_per_day.max * 100.0 / days).round(1),
      error: error
    }

    # Generate an ASCII table
    table = Terminal::Table.new do |t|
      t.title = "Date Range Simulation Results: max #{max_period} days"
      t.headings = %w[Metric Value Comments]

      t.add_row ["Days", stats[:days], ""]
      t.add_row ["Everytime", stats[:everytime], ""]
      t.add_row ["Max Period", stats[:max_period], ""]
      t.add_row ["Coverage", "#{stats[:coverage_percentage]}%", ""]
      t.add_row ["Unchecked Days", stats[:unchecked_days], "Should be zero, was: #{unchecked_dates.inspect}"]
      t.add_row ["Max Unchecked Streak", stats[:max_unchecked_streak], "Should be < #{max_period}"]
      t.add_row ["Avg Checked Per Day%", stats[:avg_checked_per_day], "Should be approx #{(100 / max_period).round(1)}"]
      t.add_row ["Min Checked Per Day%", stats[:min_checked_per_day], ""]
      t.add_row ["Max Checked Per Day%", stats[:max_checked_per_day], ""]
    end

    stats_with_table = stats.merge({ table: table })

    # Create visualization if there was an error or explicitly requested
    if error || visualize
      create_visualization(simulation_history, error, {
        start_date: start_simulation_date, # Show 20 days before the simulation start
        end_date: today + 1, # Show 2 days after the simulation end
        max_period: max_period,
        days: days,
        everytime: everytime
      })
    end

    stats_with_table
  end

  # Create visualization of simulation results
  # @param simulation_history [Hash] History of simulation runs Array of [from_date, to_date, comment]
  # @param error [Hash, nil] Error information if any
  # @param config [Hash] Configuration for visualization
  # @return [String] Path to the generated HTML file
  def self.create_visualization(simulation_history, error, config)

    # Create the visualizer
    visualizer = DateRangeVisualizer.new(
      simulation_history,
      error,
      config
    )

    # Generate the visualization
    visualizer.visualize
  end
end
