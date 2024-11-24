# waterfinity

Finite liquids implementation for modern Minetest.

## Physics

* *Source* liquid always tries to produce more flowing liquid.
* *Flowing* liquid evens out with its neighbours.
* Thin liquid runs towards holes up to N blocks away.
* If the `Jittering` setting is enabled, almost even liquid will jitter around randomly, so all bodies even out "eventually".

## Mod support

* `default`: Finite water and lava replace the 'regular' variants in generation.
* `buckets`: Custom buckets are supported with basic liquid pickup/place logic. Proper liquid pointing will be available with MT 5.9.
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
    bucket_images = {
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_1.png",
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_2.png",
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_3.png",
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_4.png",
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_5.png",
        "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_6.png",
        "waterfinity_bucket_water.png^waterfinity_bucket_bar_7.png",
    }
}
```

* `source`: Optional. The node for the 'spring' liquid. Infinite, always tries to produce more liquid, absorbs liquid from above.
* `flowing`: The node for the finite liquid.
* `drain_range`: Defaults to 3. How far thin liquid will run towards holes.
* `jitter`: Defaults to true. Whether almost even bodies will jitter when the `Jittering` setting is enabled.
* `bucket`: Optional. The prefix for bucket items to be registered for the liquid. E.G. "waterfinity:bucket_water_1"
* `bucket_desc`: The description for bucket items. E.G. "S("Finite Water Bucket")"
* `bucket_images`: A list of bucket item textures.