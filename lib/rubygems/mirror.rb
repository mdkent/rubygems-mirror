require 'rubygems'
require 'fileutils'

class Gem::Mirror
  autoload :Fetcher, 'rubygems/mirror/fetcher'
  autoload :Pool, 'rubygems/mirror/pool'
  attr_reader :specs_files

  RELEASE_SPECS_FILES = [ "specs.#{Gem.marshal_version}" ]
  PRERELEASE_SPECS_FILES = [ "prerelease_specs.#{Gem.marshal_version}" ]
  PRE_AND_RELEASE_SPECS_FILES = RELEASE_SPECS_FILES + PRERELEASE_SPECS_FILES

  DEFAULT_URI = 'http://production.cf.rubygems.org/'
  DEFAULT_TO = File.join(Gem.user_home, '.gem', 'mirror')

  RUBY = 'ruby'

  def initialize(from = DEFAULT_URI, to = DEFAULT_TO, parallelism = 10, prerelease = false)
    @from, @to = from, to
    @fetcher = Fetcher.new
    @pool = Pool.new(parallelism)
    @prerelease = prerelease
    @specs_files = prerelease ? PRE_AND_RELEASE_SPECS_FILES : RELEASE_SPECS_FILES
  end

  def from(*args)
    File.join(@from, *args)
  end

  def to(*args)
    File.join(@to, *args)
  end

  def update_specs
    @specs_files.each do |sf|
      sfz = "#{sf}.gz"

      specz = to(sfz)
      @fetcher.fetch(from(sfz), specz)
      open(to(sf), 'wb') { |f| f << Gem.gunzip(File.read(specz)) }
    end
  end

  def gems
    gems = []
    
    @specs_files.each do |sf|
      update_specs unless File.exists?(to(sf))

      gems += Marshal.load(File.read(to(sf)))
    end

    gems.map! do |name, ver, plat|
      # If the platform is ruby, it is not in the gem name
      "#{name}-#{ver}#{"-#{plat}" unless plat == RUBY}.gem"
    end

    gems
  end

  def existing_gems
    Dir[to('gems', '*.gem')].entries.map { |f| File.basename(f) }
  end

  def gems_to_fetch
    gems - existing_gems
  end

  def gems_to_delete
    existing_gems - gems
  end

  def update_gems
    gems_to_fetch.each do |g|
      @pool.job do
        @fetcher.fetch(from('gems', g), to('gems', g))
        yield
      end
    end

    @pool.run_til_done
  end

  def delete_gems
    gems_to_delete.each do |g|
      @pool.job do
        File.delete(to('gems', g))
        yield
      end
    end

    @pool.run_til_done
  end

  def update
    update_specs
    update_gems
    cleanup_gems
  end
end
