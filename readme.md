# waterfinity

Finite liquids implementation for modern Minetest.

## Physics

* *Source* liquid always tries to produce more flowing liquid.
* *Flowing* liquid evens out with its neighbours.
* Thin liquid runs towards nearby holes.
* If the `Jitter` setting is enabled, almost even liquid will jitter around every so often, so all bodies even out "eventually".

## Mod support

* `default`: Finite water and lava replace the 'regular' variants in generation.
* `buckets`: Custom buckets are supported with basic liquid pickup/place logic.
* `mesecons`: Pistons can push into liquids and compress them against blocks. (WIP)

## API

```
waterfinity.register_liquid {
    source = "waterfinity:spring",
    flowing = "waterfinity:water",
    
    drain_range = 3,
    jitter = true,
    
    bucket = "waterfinity:bucket_water",
    bucket_desc = S("Finite Water Bucket"),
    bucket_images = {...}
}
```

* `source`: Optional. The node for the 'source' liquid.
* `flowing`: The node for the finite liquid.
* `drain_range`: Defaults to 3. How far thin liquid can run towards holes.
* `jitter`: Defaults to true. Whether almost even bodies will jitter when the `Jitter` setting is enabled.
* `bucket`: Optional. The prefix for bucket items to be registered for the liquid.
* `bucket_desc`: The description for bucket items.
* `bucket_images`: An array of bucket item textures, from one layer to full.

```
waterfinity.bucket_textures("waterfinity_bucket_water_part.png", "waterfinity_bucket_water.png")
```

Helper function for generating bucket textures with the fancy bar and all. First texture is optional and will be used only for non-full buckets.