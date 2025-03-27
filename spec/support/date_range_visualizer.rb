# frozen_string_literal: true

require 'fileutils'
require 'date'
require 'erb'

# A helper class to visualize date range simulation results
class DateRangeVisualizer
  # @return [Date]
  attr_reader :simulation_history, :error_data, :start_date, :end_date
  # @return [Integer]
  attr_reader :max_period, :everytime, :days

  MAX_ROWS = 40
  MAX_COLUMNS = 50

  CSS_CLASSES = %w[searched-0 searched-1 searched-2 searched-3 searched-4]
  CSS_DEFAULT_CLASS = "searched-other"

  # Initialize the visualizer with simulation data
  # @param simulation_history [Hash] Hash with Date objects as keys and arrays of [from_date, to_date, comment]
  # @param error_data [Hash, nil] Error information if an error occurred containing:
  # * streak [Integer] Number of days unchecked
  # * found_on [Date] Date streak was discovered past acceptable limits
  # * search_date: [Date] The date that wasn't checked frequently enough
  # * last_checked: [Date] The last simulated "today" that this search_date was part of the search range
  #   (it may be out of the display range)
  # * message: [String] A message detailing the above details

  # @param config [Hash{Symbol => Integer, Date}] Configuration parameters
  def initialize(simulation_history, error_data, config)
    @simulation_history = simulation_history
    @error_data = error_data
    if @error_data
      msg = "error_data: #{@error_data.inspect}"
      unless @error_data[:streak].is_a? Integer
        raise "error_data[:streak] was #{@error_data[:streak].inspect} not Integer! #{msg}"
      end
      unless @error_data[:found_on].is_a? Date
        raise "error_data[:found_on] was #{@error_data[:found_on].inspect} not Date! #{msg}"
      end
      unless @error_data[:last_checked].is_a? Date
        raise "error_data[:last_checked] was #{@error_data[:last_checked].inspect} not Date! #{msg}"
      end
      unless @error_data[:search_date].is_a? Date
        raise "error_data[:search_date] was #{@error_data[:search_date].inspect} not Date! #{msg}"
      end
    end
    @start_date = config[:start_date] || Date.today - 30
    @end_date = config[:end_date] || Date.today
    @max_period = config[:max_period] || 5
    @everytime = config[:everytime] || 1
    @days = config[:days] || 30
    # days to correspond to CSS_CLASSES
    @css_days = []
    @css_other_days = []
  end

  # Generate HTML visualization and save to file
  # @return [String] Path to the saved HTML file
  def visualize
    html = generate_html

    # Create logs directory if it doesn't exist
    log_dir = File.join(Dir.pwd, 'log')
    FileUtils.mkdir_p(log_dir)

    filename = File.join(log_dir, "visualize_simulation-#{@max_period}.html")

    # Write HTML to file
    File.write(filename, html)
    puts "Visualization of max_period=#{@max_period} saved to #{filename}"
    filename
  end

  def today_coverage(today_date)
    count_all = [all_dates.select { |d| d <= today_date }.size, 1].max
    count_covered = 0
    history = @simulation_history[today_date] || []
    history.each do |from_date, to_date, _comment|
      effective_from = [from_date, first_search_date].max
      days = to_date + 1 - effective_from
      count_covered += days if days&.positive?
    end
    (count_covered * 100.0 / count_all).round(1)
  end

  def search_coverage(search_date)
    count_all = [today_dates.select { |d| d >= search_date }.size, 1].max
    count_covered = 0
    today_dates.each do |today_date|
      history = @simulation_history[today_date] || []
      history.each do |from_date, to_date, _comment|
        effective_from = [from_date, first_search_date].max
        if effective_from <= search_date && search_date <= to_date
          count_covered += 1
          break
        end
      end
    end
    (count_covered * 100.0 / count_all).round(1)
  end

  private

  # Generate HTML content for visualization
  # @return [String] HTML content
  def generate_html
    erb = ERB.new(template)
    erb.result(binding)
  end

  # Get template for visualization
  # @return [String] ERB template
  def template
    File.read(__FILE__.sub(/\.rb$/, '.html.erb'))
  end

  # Format date as "DD MMM"
  # @param date [Date] Date object
  # @return [String] Formatted date string
  def format_date(date)
    date.strftime('%d %b')
  end

  # Get all dates in the range to be visualized
  # @return [Array<Date>] All dates in the range
  def all_dates
    (@start_date..[today_dates.last, @end_date].min).to_a.last(MAX_COLUMNS)
  end

  # Get all "today" dates in the simulation
  # @return [Array<Date>] All "today" dates sorted
  def today_dates
    @simulation_history.keys.sort.last(MAX_ROWS)
  end

  # First search_date on X axis
  def first_search_date
    @first_search_date ||= all_dates.first
  end

  # Determine cell class and content
  # @param today_date [Date] Today's date
  # @param search_date [Date] Date being searched
  # @return [Array<String, String, String, Integer, Integer>] CSS class, title, cell content, col and row span (or empty array for no cell)
  def cell_details(today_date, search_date)
    # Future dates can't be searched

    boundary_class = class_for_boundary((today_date - search_date).to_i)
    default = display_skipped(boundary_class)
    if search_date > today_date || search_date <= today_date - @days
      default = display_ignored
    end

    # Check if this date is searched on this "today"
    history = @simulation_history[today_date] || []
    history.each do |from_date, to_date, comment|
      effective_from = [from_date, first_search_date].max
      if effective_from <= search_date && search_date <= to_date
        # In search range
        if effective_from == search_date
          return display_range(boundary_class, from_date, to_date, comment)
        else
          default = []
        end
      end
    end

    # Check if this is an error streak
    effective_from = [@error_data[:last_checked] + 1, first_search_date].max if @error_data
    if @error_data && search_date == @error_data[:search_date] && effective_from <= today_date
      if today_date == effective_from
        return display_error(today_date)
      else
        default = []
      end
    end

    default
  end
  
  def class_for_boundary(days_ago)
    days_ago -= @everytime - 1
    if [0, 1 + 2*2, 2 + 2*2 + 3*3, 3 + 2*2 + 3*3 + 5*5].include? days_ago
      "period-boundary"
    end    
  end

  def display_error(today_date)
    row_span = [@error_data[:found_on] + 1 - today_date, 1].max
    ["error-streak", @error_data[:message] || "ERROR", "E<wbr>rr<wbr>or", 1, row_span]
  end

  def rationalize_css_classes
    if @css_other_days.size == 1
      @css_days << @css_other_days.first
      @css_other_days = []
    end
  end

  def display_range(boundary_class, from_date, to_date, comment)
    effective_from = [from_date, first_search_date].max
    col_span = (to_date + 1 - effective_from).to_i
    days = (to_date + 1 - from_date).to_i
    css_index = @css_days.index(days)
    if css_index.nil?
      if @css_days.size < CSS_CLASSES.size
      css_index = @css_days.size
      @css_days << days
      else
        @css_other_days << days unless @css_other_days.index(days)
      end
    end
    css_index ||= CSS_CLASSES.size
    [
      "searched-#{css_index} #{boundary_class}",
      "#{format_date from_date} .. #{format_date to_date}",
      comment,
      col_span,
      1
    ]
  end

  def display_skipped(boundary_class)
    ["skipped #{boundary_class}", nil, "", 1, 1]
  end

  def display_ignored
    ["ignore", nil, "", 1, 1]
  end

end
