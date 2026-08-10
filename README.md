# revShuffler

Imaging you having bought a bunch of images from various places. This little app is supposed to help you, create a habit of daily drawing practice.

Whenever the user selects a folder, a .revShuffler file gets created inside that folder. This file contains an array of structs, containing information about the image path and how often it was drawn/shown. Therefore revShuffler can sort that array and show you images, you have seen the least amount of times. 


## The idea is:

 **Open the app -> get an image -> draw -> save your progress -> come back tomorrow.**


## The `.revShuffler` file

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
