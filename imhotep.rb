require 'nokogiri'
require 'open-uri'

URL = "http://www.bbc.co.uk/education/guides/ztndmp3/revision" # Hardcoded for testing
PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
USER_AGENT = "imhotep.rb BBC K&L Infographics checker"
DOMAIN = "http://www.bbc.co.uk"
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/

class Scraper
#	@site
	@url

	def initialize(url)
		@url = url
	#	@site = Array.new

		self.scrape(@url)
	end

	def scrape(url)
		start_page = Page.new(url)
		pages = Array.new

		pages = start_page.extract_urls.collect if start_page.index?
		
		pages.each do |page|
			puts page
			self.scrape(page) if page.index?
		end
	end
end

class Page
	@page
	@images

	def initialize(url)
		@page = Nokogiri::HTML(open(url, :proxy => PROXY, "User-Agent" => USER_AGENT))
		@images = Array.new
	end

	def index?
		@page.xpath("//section/@class").each do |section|
			return true if section.content["topics"]	# PROBLEM - main index doesn't have this
		end
		false
	end

	def extract_images
		@page.xpath("//article//img/@src").each do |image|
			@images << {:pid => image.content[REGEX_GRAPHICS, 1], :size => image.content[REGEX_GRAPHICS, 2]}
		end
		@images
	end

	def extract_urls
		url_array = Array.new

		@page.xpath("//section[contains(@class,'topics')]//ol/li//a").each do |link|
			url_array << DOMAIN + link.attr('href') if link.attr('title') == "Revise"
		end
		url_array
	end
end

class MigrationLog
	#TODO
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

example4 = Scraper.new("http://www.bbc.co.uk/education/subjects/zgm2pv4")