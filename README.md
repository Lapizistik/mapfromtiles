# mapfromtiles #

Script to download some tiles from a tileserver and stitch them together
to one larger image to be printed for *personal* use.

## Warning ##

You **must not** download larger amounts of tiles without asking the tiles provider first.
Always comply to their policy (see e.g. the [OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/) for https://www.openstreetmap.org/).

You should also give some identifier (your webpage or email-address) where the
provider could contact you, otherwise you may get banned.

## Caveat ##

The script currently does not deal with the 180°/-180° overlap (TODO)

## Usage ##

```ruby
mft = MapFromTiles.new(
  contact: 'yourcontactinformation, e.g. email/webpage',
  provider: :osmde
)

mft.map2img(lat1: 48.20200, lon1: 16.37100, lat2: 48.20300, lon2: 16.37300, imgfile: '/tmp/mymap.png')
```
TODO
