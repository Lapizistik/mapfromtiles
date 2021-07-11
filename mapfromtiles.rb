#!/usr/bin/env ruby

# TODO: deal with the overflow at -180°–180°
# TODO: include retina tiles

require 'fileutils'
require 'open-uri'
require 'pathname'

class MapFromTiles
  TILESIZE = 250

  # current work dir (if exists)
  attr_accessor :tilesdir
  
  # current tmpdir (to create workdir in)
  # on some systems you may want to use /var/tmp
  attr_accessor :tmpdir

  # whether to keep or delete tiles directory after processing
  # (if `tilesdir` it is always kept (may change)).
  attr_accessor :keep_tilesdir

  # whether to overwrite existing tiles and redownload all
  attr_accessor :overwrite_tiles

  # maximum nr of tiles for the resulting image
  # (safeguard not to accidently download the world)
  attr_accessor :maxtiles

  # Debugging mode
  attr_accessor :debug

  # the request headers sent to the server
  attr_accessor :http_headers
  
  # provider is either a key (String or Symbol) for MapFromTiles::Provider
  # or a Hash with at least the key :url
  def initialize(provider: :osm,
                 maxtiles: 100,
                 tmpdir: Dir.tmpdir,
                 tilesdir: nil,
                 keep_tilesdir: true,
                 overwrite_tiles: false,
                 debug: false,
                 contact:
                )
    @provider = get_provider(provider)
    @maxtiles = maxtiles
    @tmpdir = tmpdir
    @tilesdir = tilesdir
    @keep_tilesdir = keep_tilesdir
    @overwrite_tiles = overwrite_tiles
    @debug = debug
    @http_headers = http_request_headers(contact)
  end

  def map2img(lat1:, lon1:, lat2:, lon2:, zoom: 18, imgfile:,
              provider: @provider)

    x1, y1 = *get_tile_number(lat1, lon1, zoom)
    x2, y2 = *get_tile_number(lat2, lon2, zoom)

    # TODO: deal with -180°/180° overlap (e.g. by seperating and combining)
    x1, x2 = x2, x1 if x1 > x2
    y1, y2 = y2, y1 if y1 > y2

    n_tiles = (x1..x2).size * (y1..y2).size
    
    if @debug
      warn "xr = #{x1}..#{x2}, yr = #{y1}..#{y2}, zoom = #{zoom}"
    end
    
    if n_tiles > @maxtiles
      raise "Would need to request #{n_tiles} > #{@maxtiles}. Aborting"
    end

    if keep_tilesdir || @tilesdir
      @tilesdir ||= Dir.mktmpdir('mapfromtiles', @tmpdir)
      FileUtils.mkdir_p(@tilesdir) unless Dir.exist? @tilesdir
      fetch_and_stitch(provider: get_provider(provider), imgfile: imgfile,
                       xr: (x1..x2), yr: (y1..y2), zoom: zoom)
    else
      Dir.mktmpdir('mapfromtiles', @tmpdir) do |dir|
        @tilesdir = nil
        fetch_and_stitch(provider: get_provider(provider),  imgfile: imgfile, dir: dir,
                         xr: (x1..x2), yr: (y1..y2), zoom: zoom)
      end
    end
  end

  def fetch_and_stitch(xr:, yr:, zoom:, provider: get_provider(@provider),
                       dir: @tilesdir, attr: provider[:attribution], imgfile:)
    (zoom <= (provider[:maxZoom] || 99)) or raise "Zoomlevel #{zoom} to high for this provider"
    dir = Pathname.new(dir)

    tiles = []
    yr.each do |y|
      xr.each do |x|
        tiles << fetch(provider, x, y, zoom, dir).to_s
      end
    end
    system('montage', *tiles, '-mode', 'Concatenate', '-tile', "#{xr.size}x#{yr.size}", imgfile)
    if attr
      system('mogrify', '-gravity', 'southeast', '-pointsize', '8', '-annotate', '0x0-0-0', attr, imgfile)
    end
  end

  def fetch(provider, x, y, zoom, dir, http_headers = @http_headers)
    url = provider[:url].
      sub(/\{s\}/) { %w[a b c].sample }.
      sub(/\{x\}/) { x }.
      sub(/\{y\}/) { y }.
      sub(/\{z\}/) { zoom }.
      sub(/\{r\}/) { '' } # maybe we should support retina?
    filename = dir / "#{x}-#{y}-#{zoom}.png"
    if File.exist?(filename ) && !@overwrite_tiles
      warn "“#{filename}” already exists, skipping download"
    else
      warn "fetching “#{url}”" if @debug

      File.write(filename,
                 URI.open(url, http_headers) { |con| con.read })
    end
    filename
  end

  def get_provider(p)
    if p.respond_to?(:to_sym)
      p = Provider[p.to_sym] or raise "unknown provider #{p}"
    end
    if p.respond_to?(:to_h)
      provider = p
    else
      raise "wrong provider format: #{p.inspect}"
    end
    provider
  end

  # we generate the request headers from the user's whoami
  # and the softwares identification
  def http_request_headers(contact)
    h = { "User-Agent" => "MFT (https://github.com/Lapizistik/mapfromtiles, contact: #{contact}) " }
    # is it an email address?
    h['From'] = contact if (contact !~ %r{//:}) && (contact =~ /.+@.+/)
    h
  end
  
  # the convert method code is from
  # https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
  def get_tile_number(lat_deg, lng_deg, zoom)
    lat_rad = lat_deg/180 * Math::PI
    n = 2.0 ** zoom
    [((lng_deg + 180.0) / 360.0 * n).to_i,
     ((1.0 - Math::log(Math::tan(lat_rad) +
                       (1 / Math::cos(lat_rad))) /
         Math::PI) / 2.0 * n).to_i]
  end

  # s: subdomain = {a,b,c}
  # r: nil, "@2x" for high res tiles
  Provider = {
    osm: {
      name: 'OpenStreetMap',
			url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxZoom: 19,
      attribution: 'ⓒ OpenStreetMap contributors',
      policy: {
        url: 'https://operations.osmfoundation.org/policies/tiles/',
        minZoom: 13,
        maxtiles: 250
      }
    },
    osmde: {
      name: 'OpenStreetMap DE',
			url: 'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png',
      maxZoom: 18,
      attribution: 'ⓒ OpenStreetMap contributors'
    },
    osmfr: {
      name: 'OpenStreetMap FR',
			url: 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap France, OpenStreetMap contributors'
    },
    osmhot: {
      name: 'OpenStreetMap HOT',
			url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxZoom: 19,
      attribution: 'ⓒ OpenStreetMap contributors, tiles style by Humanitarian OpenStreetMap Team, hosted by OpenStreetMap France'
    },
    otm: {
      name: 'OpenTopoMap',
			url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      maxZoom: 17,
      attribution: 'ⓒ OpenStreetMap contributors, tiles style by OpenTopoMap'
    },
    stadia_as: {
      name: 'Stadia Alidade smooth',
			url: 'https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ Stadia Maps, OpenMapTiles, OpenStreetMap contributors'
    },
    stadia_osmb: {
      name: 'Stadia OSM bright',
			url: 'https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ Stadia Maps, OpenMapTiles, OpenStreetMap contributors'
    },
    stadia_out: {
      name: 'Stadia Outdoors',
			url: 'https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ Stadia Maps, OpenMapTiles, OpenStreetMap contributors'
    },
    stamen_toner: {
      name: 'Stamen Toner',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/toner/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    stamen_toner_bg: {
      name: 'Stamen Toner background',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/toner-background/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    stamen_toner_lite: {
      name: 'Stamen Toner lite',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/toner-lite/{z}/{x}/{y}{r}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    stamen_wc: {
      name: 'Stamen Watercolor',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/watercolor/{z}/{x}/{y}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    stamen_terrain: {
      name: 'Stamen Terrain',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/terrain/{z}/{x}/{y}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    stamen_terrain_bg: {
      name: 'Stamen Terrain background',
      url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/terrain-background/{z}/{x}/{y}.png',
      maxZoom: 20,
      attribution: 'ⓒ OpenStreetMap contributors, map tiles by Stamen Design, CC-BY 3.0'
    },
    tf_pio: {
      name: "Thunderforest Pioneer",
      url: 'https://{s}.tile.thunderforest.com/pioneer/{z}/{x}/{y}.png',
      apikey: ENV['THUNDERFOREST_APIKEY'],
      maxZoom: 22,
      attribution: 'ⓒ Thunderforest, OpenStreetMap contributors',
    },
    carto_pos: {
      name: 'CartoDB Positron',
      url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      maxZoom: 19,
      attribution: 'ⓒ OpenStreetMap contributors, CARTO'
    },
    basemap_at: {
      name: 'Basemap AT',
      url: 'https://maps.wien.gv.at/basemap/geolandbasemap/{type}/google3857/{z}/{y}/{x}.png',
      maxZoom: 20,
      attribution: 'Datenquelle: https://basemap.at'
    }
  }.each {|k,v| v[:pkey] = k }

end

