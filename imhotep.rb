require 'optparse'
require 'nokogiri'
require 'open-uri'
require 'roo'
require 'csv'
require 'fastimage'

PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
USER_AGENT = "imhotep.rb BBC K&L Infographics checker"
DOMAIN = "http://www.bbc.co.uk"
SITE = "education"
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/
REGEX_GRAPHICS_SIZES_TEXT = /large|medium|small/
REGEX_PHOTOS = /\/ic\/320xn\/(p[a-z0-9]{6,})\./
REGEX_PIDS = /(?:z|p)\w+/
REGEX_URLS = /(?:subjects|topics|guides)\/z[a-z0-9]{6}/
REGEX_LOG = /\.xlsx\z/

$errors = Array.new

class Optparser
	def self.parse(args)
		options = {}
		options[:graphics] = true
		options[:photos] = false

		option_parser = OptionParser.new do |opts|
			opts.banner = "Usage: imhotep.rb [options]"
			opts.separator ""
			opts.separator "Specific options:"

			opts.on("-u", "--url PATH", "Scrape the specified page (in the format 'topics/z012345')") do |url|
				options[:url] = url
			end

			opts.on("-l", "--log LOG.XLSX", "Use the specified migration log") do |log|
				options[:log] = log
			end

			opts.on("-g", "--graphics", "Check for images in the graphics tab (default)") do |g|
				options[:graphics] = g
				options[:photos] = false
			end

			opts.on("-p", "--photos", "Check for images in the photos tab") do |p|
				options[:photos] = p
				options[:graphics] = false
			end

			opts.on("-b", "--both", "Check for images in both the graphics and photos tabs") do |b|
				options[:graphics] = b
				options[:photos] = b
			end

			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				exit
			end

			puts opts if args.empty?
		end

		option_parser.parse!(args)
		raise OptionParser::MissingArgument if options[:url].nil? || options[:log].nil?
		options
	end
end

class Optchecker
	def initialize(options)
		exit unless options
		self.check_options(options)
	end

	def check_options(options)
		unless options[:url] = options[:url][REGEX_URLS]
			puts "Invalid URL PATH, needs to be in the format '[subjects/topics/guides]/pid'"
			puts "Example: 'subjects/zgm2pv4'"
			exit
		end

		unless options[:log][REGEX_LOG] && File::exists?(options[:log])
			puts "Invalid MIGRATION LOG, needs to exist and end with '.xlsx'"
			exit
		end

		options[:url] = DOMAIN + "/" + SITE + "/" + options[:url]
		self.start_program(options)
	end

	def start_program(options)
		scraper = Scraper.new(options[:url], options[:graphics], options[:photos])
		if options[:graphics]
			log_graphics = Migrationlog.new(options[:log], "graphics")
			log_graphics.compare_pids(scraper)
			log_graphics.write_results(options[:url], options[:log], "Graphics")
		end
		if options[:photos]
			log_photos = Migrationlog.new(options[:log], "photos")
			log_photos.compare_pids(scraper)
			log_photos.write_results(options[:url], options[:log], "Photos")
		end
		Errorwriter.write_errors
	end
end

class Scraper
	@url
	@images
	@options
	attr_reader :images

	def initialize(url, graphics, photos)
		@url = url
		@images = Array.new
		@options = {:graphics => graphics, :photos => photos}

		puts "Starting scrape..."

		self.scrape(@url)
	end

	def scrape(url)
		begin
			start_page = Page.new(url, @options)
			pages = Array.new

			start_page.index? ? pages = start_page.extract_urls.collect : pages << url
			
			pages.each do |page|
				current_page = Page.new(page, @options)
			#	puts page
				if current_page.index?
					puts "\n#{page}"
					self.scrape(page)
				else
					print "#"
					current_page.extract_images.each { |image| @images << image }
					self.scrape(current_page.more) if current_page.more
				end
			end
		rescue OpenURI::HTTPError
			puts "Skipping..."
		end
	end

	def found(pid)
		@images.find_all { |image| image[:pid] == pid }
	end

	def found?(pid)
		return true if @images.detect { |image| image[:pid] == pid }
		false
	end
end

class Page
	@url
	@page
	@images
	@options

	def initialize(url, options = {})
		@url = url
		@images = Array.new
		@options = options

		begin
			@page = Nokogiri::HTML(open(@url, :proxy => PROXY, "User-Agent" => USER_AGENT))
		rescue OpenURI::HTTPError => e
			puts "\nERROR: #{e.message}"
			puts "Failure URL: #{@url}"
			$errors << {:error => e.message, :url => @url}
			raise
		end
	end

	def index?
		@page.xpath("//section/@class").each do |section|
			return true if section.content["topics"] && !clips?
		end
		false
	end

	def clips?
		@page.xpath("//section/div/ul/li/@class").each do |li|
			return true if li.content["c-cgf-1-tab-clips"] && li.content["k-is-selected"]
		end
		false
	end

	def more
		@page.xpath("//div[contains(@class, 'k-icon-arrow-right') and not(contains(@class, 'k-inactive'))]/a").each do |next_url|
			return DOMAIN + next_url.attr('href') if next_url.attr('href')[/\/revision/]
		end
		false
	end

	def extract_images
		if @options[:graphics]
			@page.xpath("//article//img/@src|//form//img/@src").each do |image|
				if @options[:graphics] && image.content[REGEX_GRAPHICS]
					sizes = Hash.new
					image_root = image.content.sub(REGEX_GRAPHICS_SIZES_TEXT, '')
					sizes[:small] = FastImage.size(image_root + 'small') || 0 # Chance to make this bit DRYer
					sizes[:medium] = FastImage.size(image_root + 'medium') || sizes[:small]
					sizes[:large] = FastImage.size(image_root + 'large') || sizes[:small]
					@images << {:pid => image.content[REGEX_GRAPHICS, 1], :size => sizes, :url => @url}
				elsif @options[:photos] && image.content[REGEX_PHOTOS]
					@images << {:pid => image.content[REGEX_PHOTOS, 1], :url => @url}
				end
			end
		end
		@images
	end

	def extract_urls
		url_array = Array.new

		@page.xpath("//section[contains(@class,'topics')]//ol/li//a").each do |link|
			url_array << DOMAIN + link.attr('href') unless link.attr('title') && link.attr('title') == "Revise" # Avoids repetition of Revision link while allowing topic, test, and first instance of revision links
		end
		url_array
	end
end

class Migrationlog
	@migration_log
	@result_log
	@pids
	@mode

	def initialize(log, mode)
		@migration_log = Roo::Excelx.new(log)
		if mode == "photos"
			@migration_log.sheet(1)
			@mode = 1
		else
			@migration_log.sheet(0)
			@mode = 0
		end
		@result_log = Array.new
		@pids = Array.new

		self.extract_pids
	end

	def extract_pids
		if @mode == 0
			@migration_log.each(:job => 'Job No', :filename => 'New filename', :pid => 'PIDs', :large => 'Large width', :medium => 'Medium width', :small => 'Small width') do |row| # Chance to make this DRYer
				row[:large], row[:medium], row[:small] = row[:large].to_i, row[:medium].to_i, row[:small].to_i
				@pids << row if row[:pid][REGEX_PIDS]
			end
		else
			@migration_log.each(:job => 'Job No', :filename => 'New filename', :pid => 'PIDs') do |row|
				@pids << row if row[:pid][REGEX_PIDS]
			end
		end
	end

	def compare_pids(scraper)
		puts "\nNow comparing..."
		@pids.each do |pid|
			if scraper.found?(pid[:pid])
				scraper.found(pid[:pid]).each do |page|
					failure = Array.new
					if @mode == 0
						failure << {:size => :large, :value => page[:size][:large][0], :expected => pid[:large]} unless page[:size][:large][0] == pid[:large]
						failure << {:size => :medium, :value => page[:size][:medium][0], :expected => pid[:medium]} unless page[:size][:medium][0] == pid[:medium]
						failure << {:size => :small, :value => page[:size][:small][0], :expected => pid[:small]} unless page[:size][:small][0] == pid[:small]
					end
					if failure.size > 0
						@result_log << {:pid => pid[:pid], :job => pid[:job], :filename => pid[:filename], :failures => failure, :success => false}
						puts "IMAGE MISMATCH: Job #{pid[:job]}, PID #{pid[:pid]}"
					else
						@result_log << {:pid => pid[:pid], :job => pid[:job], :filename => pid[:filename], :url => page[:url], :success => true}
					end
				end
			else
				@result_log << {:pid => pid[:pid], :job => pid[:job], :filename => pid[:filename], :success => false}
				puts "NOT FOUND: Job #{pid[:job]}, PID #{pid[:pid]}"
			end
		end
	end

	def write_results(url, log, mode)
		puts "Writing results..."

		CSV::open("results.csv", "ab") do |csv|
			csv << ["#{mode} results for #{url} vs #{log}"]
			csv << ["FAILURES"]
			csv << ["Job No.", "Filename", "PID", "Other"]
			@result_log.each do |line|
				if line[:failures]
					csv << [line[:job], line[:filename], line[:pid], format_failures(line[:failures])]
				else
					csv << [line[:job], line[:filename], line[:pid]] unless line[:success]
				end
			end
			csv << [""]
			csv << ["SUCCESSES"]
			csv << ["Job No.", "Filename", "PID", "URL"]
			@result_log.each do |line|
				csv << [line[:job], line[:filename], line[:pid], line[:url]] if line[:success]
			end
			csv << [""]
		end
		puts "Complete"
	end

	private
	def format_failures(failures)
		formatted_failures = "IMAGE SIZES: "
		failures.each do |failure|
			formatted_failures << "|| #{failure[:size]} is #{failure[:value]}, expected #{failure[:expected]} "
		end
		formatted_failures
	end
end

class Errorwriter
	def self.write_errors
		CSV::open("results.csv", "ab") do |csv|
			unless $errors.empty?
				csv << ["ERRORS"]
				csv << ["Error", "URL"]
				$errors.each do |line|
					csv << [line[:error], line[:url]]
				end
				csv << [""]
			end
		end
	end
end

Optchecker.new(Optparser.parse(ARGV))