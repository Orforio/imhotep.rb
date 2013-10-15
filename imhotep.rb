require 'optparse'
require 'nokogiri'
require 'open-uri'
require 'roo'

URL = "http://www.bbc.co.uk/education/guides/ztndmp3/revision" # Hardcoded for testing
SPREADSHEET = "Test/log.xlsx"
PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
USER_AGENT = "imhotep.rb BBC K&L Infographics checker"
DOMAIN = "http://www.bbc.co.uk"
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/
REGEX_PIDS = /z\w+/

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


class Scraper
#	@site
	@url
	@images
	attr_reader :images

	def initialize(url)
		@url = url
	#	@site = Array.new
		@images = Array.new

		puts "Starting scrape..."

		self.scrape(@url)
	end

	def scrape(url)
		start_page = Page.new(url)
		pages = Array.new

		start_page.index? ? pages = start_page.extract_urls.collect : pages << url
		
		pages.each do |page|
			current_page = Page.new(page)
		#	puts page
			if current_page.index?
				print "."
			#	puts page
				self.scrape(page)
			else
				print "#"
				current_page.extract_images.each { |image| @images << image }
				self.scrape(current_page.more) if current_page.more
			end
		end
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
		@page = Nokogiri::HTML(open(@url, :proxy => PROXY, "User-Agent" => USER_AGENT))
		@images = Array.new
	end

	def index?
		@page.xpath("//section/@class").each do |section|
			return true if section.content["topics"]
		end
		false
	end

	def more
		@page.xpath("//div[contains(@class, 'k-icon-arrow-right') and not(contains(@class, 'k-inactive'))]/a").each do |next_url|
			return DOMAIN + next_url.attr('href')
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
	@pids

	def initialize
		@migration_log = Roo::Excelx.new(SPREADSHEET)
		@migration_log.sheet(0) # Hardcoded for graphics
		@pids = Array.new

		self.extract_pids
	end

	def extract_pids
		@migration_log.each(:pid => 'PIDs') do |row|
			@pids << row if row[:pid][REGEX_PIDS]
		end
	end

	def compare_pids(scraper)
		@pids.each do |pid|
			if scraper.found?(pid[:pid])
			#	puts "Found PID #{pid[:pid]}"
			else
				puts "DID NOT FIND PID #{pid[:pid]}"
			end
		end
	end

end

# TESTING BELOW
=begin
puts "Testing..."
example = Page.new(URL)
puts "Image contents of guide ztndmp3:"
puts example.extract_images
puts "Is this page an index? #{example.index?}"

example2 = Page.new("http://www.bbc.co.uk/education/topics/zdsnb9q")
puts "Is this index page (zdsnb9q) an index? #{example2.index?}"

puts "Scraping National 4 Lifeskills Maths..."
example3 = Scraper.new("http://www.bbc.co.uk/education/topics/zdsnb9q")
=end

# example4 = Scraper.new("http://www.bbc.co.uk/education/subjects/zgm2pv4") # Whole N4 LS Maths scrape
#puts example4.images

#example5 = Scraper.new("http://www.bbc.co.uk/education/topics/z8np34j")
# puts "\nFinished crawling, now comparing..."
# log = Migrationlog.new
# log.compare_pids(example4)


#example6 = Migrationlog.new

options = Optparser.parse(ARGV)
p options