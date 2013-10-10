require 'nokogiri'
require 'open-uri'

URL = "http://www.bbc.co.uk/education/guides/ztndmp3/revision" # Hardcoded for testing
PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/

class Scraper
	#example = Page.new(URL)

	#puts example.extract_info
	@site
	@url

	def initialize(url)
		@url = url
		@site = Array.new

		self.scrape(@url)
	end

	def scrape(url)
		page = Page.new(url)
		puts "Is index!" if page.index?
	end
end

class Page
	@page
	@images

	def initialize(url)
		@page = Nokogiri::HTML(open(url, :proxy => PROXY))
		@images = Array.new
	end

	def index?
		@page.xpath('//section/@class').each do |section|
			return true if section.content["topics"]
		end
		false
	end

	def extract_images
		@page.xpath('//article//img/@src').each do |image|
			@images << {:pid => image.content[REGEX_GRAPHICS, 1], :size => image.content[REGEX_GRAPHICS, 2]}
		end
		@images
	end
end

class MigrationLog
	#TODO
end

# TESTING BELOW
puts "Testing..."
example = Page.new(URL)
puts "Image contents of guide ztndmp3:"
puts example.extract_images
puts "Is this page an index? #{example.index?}"

example2 = Page.new("http://www.bbc.co.uk/education/topics/zdsnb9q")
puts "Is this index page (zdsnb9q) an index? #{example2.index?}"

puts "Scraping National 4 Lifeskills Maths..."
example3 = Scraper.new("http://www.bbc.co.uk/education/topics/zdsnb9q")