# revShuffler

Imaging you having bought a bunch of referenz-images from various places. This little app supposedly helps you, create a habit of daily drawing practice.

Whenever the user selects a folder, a .revShuffler file gets created inside that folder. This file contains an array of structs, containing information about the image path and how often it was drawn/shown. 
RevShuffler can sort that array and show you images, you have "drawn" the least amount of times. 

I can only assume whether you have actually drawn that image.

## The idea:

 **Open the app -> select a folder -> set a Timer -> draw -> save your progress -> come back tomorrow.**

## `.revShuffler` files

The `.revShuffler` file acts as the local database for a folder.

It contains an array of structs describing the images in that folder and their history. 

```json
[
	{
		"path": "/DSC9.jpg",
		"drawnCount": 0,
		"shownCount": 0,
		"usable": false
	},    
    {
		"path": "/DSC7.jpg",
		"drawnCount": 0,
		"shownCount": 0,
		"usable": false
    },
    {
		"path": "/DSC8.jpg",
		"drawnCount": 0,
		"shownCount": 1,
		"usable": false
    }
]
```
