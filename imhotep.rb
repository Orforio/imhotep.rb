require 'optparse'
require 'nokogiri'
require 'open-uri'
require 'roo'
require 'csv'

PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
USER_AGENT = "imhotep.rb BBC K&L Infographics checker"
DOMAIN = "http://www.bbc.co.uk"
SITE = "education"
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/
REGEX_PIDS = /z\w+/
REGEX_URLS = /(?:subjects|topics|guides)\/z[a-z0-9]{6}/
REGEX_LOG = /\.xlsx\z/

$errors = Array.new

class Optparser
	def self.parse(args)
		options = {}

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
		scraper = Scraper.new(options[:url])
		log = Migrationlog.new(options[:log])
		log.compare_pids(scraper)
		log.write_results(options[:url], options[:log])
		Errorwriter.write_errors
	end
end

class Scraper
	@url
	@images
	attr_reader :images

	def initialize(url)
		@url = url
		@images = Array.new

		puts "Starting scrape..."

		self.scrape(@url)
	end

	def scrape(url)
		begin
			start_page = Page.new(url)
			pages = Array.new

			start_page.index? ? pages = start_page.extract_urls.collect : pages << url
			
			pages.each do |page|
				current_page = Page.new(page)
			#	puts page
				if current_page.index?
				#	print "."
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

	def initialize(url)
		@url = url
		@images = Array.new
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
		@page.xpath("//article//img/@src|//form//img/@src").each do |image|
			@images << {:pid => image.content[REGEX_GRAPHICS, 1], :size => image.content[REGEX_GRAPHICS, 2], :url => @url} if image.content[REGEX_GRAPHICS]
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

	def initialize(log)
		@migration_log = Roo::Excelx.new(log)
		@migration_log.sheet(0) # Hardcoded for graphics
		@result_log = Array.new
		@pids = Array.new

		self.extract_pids
	end

	def extract_pids
		@migration_log.each(:job => 'Job No', :filename => 'New filename', :pid => 'PIDs') do |row|
			@pids << row if row[:pid][REGEX_PIDS]
		end
	end

	def compare_pids(scraper)
		puts "\nNow comparing..."
		@pids.each do |pid|
			if scraper.found?(pid[:pid])
				scraper.found(pid[:pid]).each do |page|
					@result_log << {:pid => pid[:pid], :job => pid[:job], :filename => pid[:filename], :url => page[:url], :success => true}
				end
			else
				@result_log << {:pid => pid[:pid], :job => pid[:job], :filename => pid[:filename], :success => false}
				puts "NOT FOUND: Job #{pid[:job]}, PID #{pid[:pid]}"
			end
		end
	end

	def write_results(url, log)
		puts "Writing results..."

		CSV::open("results.csv", "ab") do |csv|
			csv << ["Results for #{url} vs #{log}"]
			csv << ["FAILURES"]
			csv << ["Job No.", "Filename", "PID"]
			@result_log.each do |line|
				csv << [line[:job], line[:filename], line[:pid]] unless line[:success]
			end
			csv << [""]
			csv << ["SUCCESSES"]
			csv << ["Job No.", "Filename", "PID", "URL"]
			@result_log.each do |line|
				csv << [line[:job], line[:filename], line[:pid], line[:url]] if line[:success]
			end
		end
		puts "Complete"
	end
end

class Errorwriter
	def self.write_errors
		CSV::open("results.csv", "ab") do |csv|
			if $errors
				csv << [""]
				csv << ["ERRORS"]
				csv << ["Error", "URL"]
				$errors.each do |line|
					csv << [line[:error], line[:url]]
				end
			end
		end
	end
end

Optchecker.new(Optparser.parse(ARGV))