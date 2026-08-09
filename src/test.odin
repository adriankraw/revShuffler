package revShuffler

import "core:sort"
import "core:container/queue"
import sdl "vendor:sdl3"
import sdl_image "vendor:sdl3/image"
import ui "vendor:microui"
import "core:fmt"
import "core:os"
import "base:runtime"
import "core:strings"
import "core:math/rand"
import "core:encoding/json"


basePath := ""

state := struct {
	ui_ctx: ui.Context,
	bg: ui.Color,
	timerRunning:bool,
	b_hour: f32,
	b_minute: f32,
	b_seconds: f32,
	b_nanoseconds: f32,
	hour: f32,
	minute: f32,
	seconds: f32,
	nanoseconds: f32,
	atlas_texture: ^sdl.Texture,
}{
	bg = {90,95,200,255},
}

// Available render drivers
@require_results
get_driver_names :: proc() -> (drivers: []cstring, count: i32) {
	count = sdl.GetNumRenderDrivers()
	drivers = make([]cstring, count)
	for d in 0 ..< count {
		drivers[d] = sdl.GetRenderDriver(d)
	}
	return
}

// Return first driver found in priority list or empty cstring
set_driver_by_priority :: proc(priority_list: []cstring) -> (driver: cstring) {
	driver_list, _ := get_driver_names()
	defer delete(driver_list)
	for priority in priority_list {
		for d in driver_list {
			if d == priority {
				return priority
			}
		}
	}
	return
}

Resource:: struct {
	path:		cstring,
	drawnCount:	int,
	shownCount:	int,
	usable:		bool
}

read_stateFile::proc(basePath:string, dyn_arr:^[dynamic]Resource ){
	data, err := os.read_entire_file_from_path( strings.concatenate({basePath,".revShuffler"}), context.allocator)
	if err != nil{
		fmt.eprintfln("Failed to read directory")
	}
	defer delete(data)
	
	json_err := json.unmarshal(data, dyn_arr)
	if json_err != nil{
		fmt.eprintfln("Failed to parse json")
	}
	fmt.eprintln(dyn_arr)

	read_directory(basePath, dyn_arr)

	fmt.printfln("length %d", len(dyn_arr))
}

read_directory:: proc( basePath:string, dyn_arr: ^[dynamic]Resource){
	walker := os.walker_create(basePath)
	defer os.walker_destroy(&walker)

	clear(dyn_arr)
	for fileInfo in os.walker_walk(&walker) {
		if path, err := os.walker_error(&walker); err != nil {
			fmt.eprintfln("failed walking %s: %s", path, err)
			continue
		}
		if fileInfo.type == .Regular {
			if strings.starts_with(fileInfo.name,".") == false &&
			strings.ends_with(fileInfo.name,"jpg") == true{
			append(dyn_arr,Resource{ 
				path = strings.clone_to_cstring(fileInfo.fullpath),
				drawnCount = 0,
				shownCount = 0})	
			//fmt.printfln(fileInfo.fullpath)
			}
		}
	}
}

nextImage:: proc(imageIndex:^int, length:int) -> (int){
	stepBy := int(rand.int32_range(1,25))
	if(imageIndex^+stepBy<length){
		imageIndex^+=stepBy
	}else
	{
		if(stepBy > length){
			imageIndex^ = length
		}else{
			imageIndex^ = stepBy
		}
	}
	return stepBy
}

dialogFileCallback:: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32){
	context = runtime.default_context();
	basePath = strings.clone_from_cstring(filelist[0], context.allocator);
	read_directory(basePath, cast(^[dynamic]Resource)userdata)
	sdl.Log(filelist[0])
}

mysort:: proc(dyn_arr:^[dynamic]Resource){
	sortfactor := proc(a:Resource, b:Resource) -> int
	{ 
		return a.shownCount - b.shownCount
	}
	sort.quick_sort_proc(dyn_arr[:], sortfactor)
}

main :: proc() {

	// Not required, but good practice since many applications will use this to display "about" info.
	meta_ok := sdl.SetAppMetadata("RevShuffler", "1.0", "")

	// Initialize SDL
	sdl_ok := sdl.Init({.VIDEO})
	defer sdl.Quit()

	if !meta_ok || !sdl_ok {
		fmt.eprintln("Failed to initialize")
		return
	}

	// set driver based on priority per OS type
	driver: cstring
	when ODIN_OS == .Linux {
		driver = set_driver_by_priority({"vulkan", "gpu", "opengl", "software"})
	} else when ODIN_OS == .Windows {
		driver = set_driver_by_priority({"direct3d12", "direct3d11", "direct3d", "gpu", "opengl", "software"})
	} else when ODIN_OS == .Darwin { // metal supported on macOS 10.14+ and iOS/tvOS 13.0+
		driver = set_driver_by_priority({"metal", "gpu", "opengl", "software"})
	} else {
		driver = set_driver_by_priority({"gpu", "opengl", "software"})
	}

	if driver == nil {
		fmt.eprintfln("%s %v", "Unable to load driver from priority list for", ODIN_OS)
		return
	}

	windowWidth  :i32 = 640
	windowHeight :i32 = 480
	// note: resizing window repeatedly exposes nvidia bug
	// https://github.com/libsdl-org/SDL/issues/14278
	// check configured limit of file descriptors in os with command line: ulimit -n
	window   := sdl.CreateWindow("CodingProject", windowWidth, windowHeight, {.RESIZABLE})
	renderer := sdl.CreateRenderer(window, driver)
	//sdl.SetRenderLogicalPresentation(renderer, windowWidth, windowHeight, .LETTERBOX)
	sdl.GetWindowSize(window, &windowWidth, &windowHeight)

	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	// Enable VSync
	vsync_ok := sdl.SetRenderVSync(renderer, 1)
	if !vsync_ok {
		fmt.eprintln("Failed to enable VSync")
	}

	// Some variables for main loop
	display_id      := sdl.GetDisplayForWindow(window)
	display_mode    := sdl.GetCurrentDisplayMode(display_id)
	screenWidth	:f32 = 640
	screenHeight	:f32 = 480
	refresh_rate    := display_mode.refresh_rate
	vsync_enabled   := true
	fps_cap_enabled := true
	fps_target      := 15
	fps		: f64
	showDebug	:= false

	color: sdl.FColor = {0.05,0.05,0.05,255}

	// some data for printing debug info
	drivers, _ := get_driver_names()
	defer delete(drivers)

	controls := [][]cstring {
		{"Quit",           "Q", "ESC"},
		{"Pause Color",    "P", "LMB"},
		{"Toggle Vsync",   "V", ""},
		{"Toggle FPS Cap", "F", ""},
	}

	dyn_arr:[dynamic]Resource = {}
	defer delete(dyn_arr)

	mouseWheelMovement :f32 = 1

	imageWidth	:f32
	imageHeight	:f32
	imageAspect	:f32
	lastImageIndex	:int = -1
	imageIndex	:int = 0
	imageTex	:^sdl.Texture
	resRect		: sdl.FRect = {
		x=0,
		y=0,
		w=0,
		h=0
	}
	imageQueue: queue.Queue(int)
	queue.init(&imageQueue)

	//Timer
	state.b_hour		= 0
	state.b_minute		= 0
	state.b_seconds		=15
	state.b_nanoseconds	= 0

	state.hour		= state.b_hour
	state.minute		= state.b_minute
	state.seconds		= state.b_seconds
	state.nanoseconds	= state.b_nanoseconds

	//uI
	microUI_Context:= new(ui.Context)
	ui.init(microUI_Context)
	text_width := proc(Font: ui.Font, str: string) -> i32{
		return ui.default_atlas_text_width(Font, str)
	}
	text_height := proc(Font: ui.Font) -> i32{
		return ui.default_atlas_text_height(Font)
	}
	microUI_Context.text_width = text_width
	microUI_Context.text_height = text_height
	state.atlas_texture = sdl.CreateTexture(renderer, sdl.PixelFormat.RGBA32, .TARGET, ui.DEFAULT_ATLAS_WIDTH, ui.DEFAULT_ATLAS_HEIGHT)
	assert(state.atlas_texture != nil)
	if err := sdl.SetTextureBlendMode(state.atlas_texture, sdl.BLENDMODE_BLEND); err != true {
		fmt.eprintln("sdl.SetTextureBlendMode:", err)
		return
	}
	pixels := make([][4]u8, ui.DEFAULT_ATLAS_WIDTH * ui.DEFAULT_ATLAS_HEIGHT)
	for alpha, i in ui.default_atlas_alpha {
		pixels[i].rgb = 0xff
		pixels[i].a = alpha
	}
	if err := sdl.UpdateTexture(
		state.atlas_texture,
		nil,
		raw_data(pixels),
		4 * ui.DEFAULT_ATLAS_WIDTH,
	); err != true {
		fmt.eprintln("SDL.UpdateTexture:", err)
		return
	}
	render_texture :: proc(renderer: ^sdl.Renderer, dst: ^sdl.Rect, src: ui.Rect, color: ui.Color) {
		sdl.SetTextureAlphaMod(state.atlas_texture, color.a)
		sdl.SetTextureColorMod(state.atlas_texture, color.r, color.g, color.b)
		sdl.SetTextureScaleMode(state.atlas_texture, .NEAREST)
		sdl.RenderTexture(renderer, state.atlas_texture, 
			&sdl.FRect{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}, 
			&sdl.FRect{f32(dst.x), f32(dst.y), f32(dst.w), f32(dst.h)} 
			)
	}

	testbuf: [128]u8
	testbuflength: int
	// Main loop
	main_loop: for {

		// Get counter before whole frame
		frame_start := sdl.GetTicksNS()

		// Handle events
		for e: sdl.Event; sdl.PollEvent(&e); {
			#partial switch e.type {
			case .QUIT:
				break main_loop
			case .WINDOW_CLOSE_REQUESTED:
				break main_loop
			case .KEY_DOWN:
				if(sdl.TextInputActive(window) == true) {
					switch e.key.key{
					case sdl.K_BACKSPACE:
						ui.input_key_down(microUI_Context, ui.Key.BACKSPACE)
					}
					continue;
				}
				ui.input_key_down(microUI_Context, ui.Key(e.key.raw))
			case .KEY_UP:
				if(sdl.TextInputActive(window) == true) {
					switch e.key.key{
					case sdl.K_ESCAPE:
						if sdl.StopTextInput(window) == false{
						}
						ui.set_focus(microUI_Context, 0)
					}
					continue
				}
				ui.input_key_up(microUI_Context, ui.Key(e.key.key))

				switch e.key.key {
				case sdl.K_RIGHT:
					queue.push_back(&imageQueue, nextImage(&imageIndex, len(dyn_arr)))
				case sdl.K_LEFT:
					if(queue.len(imageQueue)>0){
						back := queue.pop_back(&imageQueue)
						if(imageIndex-back>=0){
							imageIndex-=back
						}
					}
				case sdl.K_D:
					showDebug = !showDebug
				case sdl.K_M:
					test:sdl.PropertiesID = 0
					sdl.ShowFileDialogWithProperties(sdl.FileDialogType.OPENFOLDER, nil, nil, test)
				case sdl.K_ESCAPE:
					break main_loop
				case sdl.K_V:
					vsync_enabled = !vsync_enabled
					sdl.SetRenderVSync(renderer, vsync_enabled ? 1 : sdl.RENDERER_VSYNC_DISABLED)
				case sdl.K_F:
					fps_cap_enabled = !fps_cap_enabled
				}
			case .MOUSE_BUTTON_UP:
				switch e.button.button {
					case sdl.BUTTON_LEFT:
						ui.input_mouse_up(microUI_Context, i32(e.button.x), i32(e.button.y), ui.Mouse.LEFT)
						if(sdl.TextInputActive(window) == false){
							if(microUI_Context.focus_id != 0){
								if(sdl.StartTextInput(window) == false)
								{
									fmt.println(sdl.GetError())
								}
							}
						}else{
							if(microUI_Context.focus_id == 0){
								if(sdl.StopTextInput(window) == false){
									fmt.println(sdl.GetError())
								}
							}
						}
					case sdl.BUTTON_RIGHT:
						ui.input_mouse_up(microUI_Context, i32(e.button.x), i32(e.button.y), ui.Mouse.RIGHT)
				}
			case .MOUSE_BUTTON_DOWN:
				switch e.button.button {
					case sdl.BUTTON_LEFT:
						ui.input_mouse_down(microUI_Context, i32(e.button.x), i32(e.button.y), ui.Mouse.LEFT)
					case sdl.BUTTON_RIGHT:
						ui.input_mouse_down(microUI_Context, i32(e.button.x), i32(e.button.y), ui.Mouse.RIGHT)
				}
			case .MOUSE_MOTION:
				ui.input_mouse_move(microUI_Context, i32(e.motion.x), i32(e.motion.y))
			case .MOUSE_WHEEL:
				mouseWheelMovement += (e.wheel.y/50.0)
			case .TEXT_INPUT:
				text := strings.clone_from_cstring(e.text.text)
				if(text[0]<48 || text[0]>58) {continue}
				ui.input_text(microUI_Context, text)
			}
		}

		sdl.GetWindowSize(window, &windowWidth, &windowHeight)

		ui.begin(microUI_Context)
		if (ui.begin_window(microUI_Context, "buttons", {0,0,200,100}, {.NO_TITLE, .NO_FRAME, .NO_SCROLL})){

			ui.layout_row_items(microUI_Context, 2, 0)
			if ui.button(microUI_Context, "Select Folder", opt = { .NO_SCROLL, .NO_RESIZE }) == {.SUBMIT}{
				sdl.ShowOpenFolderDialog(dialogFileCallback, &dyn_arr, window, strings.clone_to_cstring(basePath), false)
			}
			if ui.button(microUI_Context, "Save", opt = { .NO_SCROLL, .NO_RESIZE }) == {.SUBMIT}{
				mysort(&dyn_arr)
				unjson_data, unjson_err := json.marshal( dyn_arr , { 
					pretty = true,
				})
				_path := strings.concatenate({basePath,"/.revShuffler"})
				fmt.println(_path)
				err := os.write_entire_file_from_string ( _path, string(unjson_data))
				if err != nil{
					fmt.println(err)
				}
			}
			ui.end_window(microUI_Context)
		}
		if (ui.begin_window(microUI_Context, "Timer", {0,100,110,150}, {.NO_SCROLL, .ALIGN_CENTER, .AUTO_SIZE})){
			ui.layout_row(microUI_Context, {30,30,30}, 0)
			if res:=ui.number(microUI_Context, &state.hour, 1, "%02.0f"); res != {}{
				state.b_hour = state.hour
			}
			if res:=ui.number(microUI_Context, &state.minute, 1, "%02.0f"); res != {}{
				state.b_minute = state.minute
			}
			if res:=ui.number(microUI_Context, &state.seconds, 1, "%02.0f"); res != {}{
				state.b_seconds = state.seconds
			}
			ui.layout_row(microUI_Context, {90}, 0)
			if ui.button(microUI_Context, state.timerRunning?"Stop":"Start", opt = { .NO_SCROLL, .NO_RESIZE }) == {.SUBMIT}{
				state.timerRunning = !state.timerRunning
			}
			ui.end_window(microUI_Context)
		}

		ui.end(microUI_Context)

		// Set new background color
		sdl.SetRenderDrawColorFloat(renderer, color.r, color.g, color.b, color.a)
		sdl.RenderClear(renderer)

		if(len(dyn_arr)>0 && lastImageIndex!=imageIndex){
			loadStart := sdl.GetTicksNS()
			imageSur:^sdl.Surface = sdl_image.Load(dyn_arr[imageIndex].path)
			if(imageSur == nil){
				fmt.eprint(dyn_arr[imageIndex].path)
				fmt.eprintln("failed to load image")
				return;
			}
			imageWidth	= f32(imageSur.w)
			imageHeight	= f32(imageSur.h)
			imageAspect	= imageWidth/imageHeight
			sdl.DestroyTexture(imageTex)
			imageTex	= sdl.CreateTextureFromSurface(renderer, imageSur)
			sdl.DestroySurface(imageSur)

			//update the count for our saveFile
			dyn_arr[imageIndex].shownCount +=1
			fmt.println("%s: %i",dyn_arr[imageIndex].path ,dyn_arr[imageIndex].shownCount)

			//update times
			loadEnd := sdl.GetTicksNS()
			loadDelta := (loadEnd - loadStart)
			lastImageIndex = imageIndex
			frame_start += loadDelta
			state.hour		= state.b_hour
			state.minute		= state.b_minute
			state.seconds		= state.b_seconds
			state.nanoseconds	= state.b_nanoseconds
			continue
		}

		windowW:= f32(windowWidth)
		windowH:= f32(windowWidth)
		imageScale:= f32(0)

		if(imageWidth<imageHeight){
			windowH/=imageAspect
			imageScale = (f32(windowHeight)/windowH) * mouseWheelMovement
		}else{
			windowH*=imageAspect
			imageScale = (f32(windowWidth)/windowW) * mouseWheelMovement
		}

		if(windowH > f32(windowHeight)){
			windowW  = f32(windowWidth) * imageScale
			windowH	 = f32(windowHeight)* imageScale
		}
		resRect.w = windowW
		resRect.h = windowW*(1.0/imageAspect)
		resRect.x = (f32(windowWidth) - resRect.w)/2.0
		resRect.y = (f32(windowHeight)- resRect.h)/2.0

		sdl.RenderTexture(renderer, imageTex, nil, &resRect)

		if(showDebug){
			// Set font color and some debug text
			r: f32 // mini row iterator
			row :: proc(row: ^f32, height: f32) -> f32 { row^ += height; return row^ }
			sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
			sdl.RenderDebugText(renderer, 10, row(&r, 10), "hellope world!")
			sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%v", "VSync Enabled:", vsync_enabled))
			sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%v", "Refresh Rate:", refresh_rate))
			sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%v", "FPS Capped:", fps_cap_enabled))
			sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%i", "FPS Target:", fps_target))
			sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%.2f", "FPS Current:", fps))
			sdl.RenderDebugText(renderer, 10, row(&r, 20), "Found Drivers:")
			for d in drivers {
				sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%s %s", d, d == driver ? "(Loaded)":""))
			}
			sdl.RenderDebugText(renderer, 10, row(&r, 20), "Controls:")
			for c in controls {
				sdl.RenderDebugText(renderer, 10, row(&r, 10), fmt.ctprintf("%-16s%-2s%s", c[0], c[1], c[2]))
			}
		}

		ui_cmd: ^ui.Command
		for ui.next_command(microUI_Context,&ui_cmd){
			switch cmd in ui_cmd.variant{
			case ^ui.Command_Text:
				//redner text
				dst := sdl.Rect{cmd.pos.x, cmd.pos.y, 0, 0}
				for ch in cmd.str do if ch & 0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := ui.default_atlas[ui.DEFAULT_ATLAS_FONT + r]
					dst.w = src.w
					dst.h = src.h
					render_texture(renderer, &dst, src, cmd.color)
					dst.x += dst.w
				}
			case ^ui.Command_Rect:
				sdl.SetRenderDrawColor(renderer,cmd.color.r,cmd.color.g,cmd.color.b,cmd.color.a)	
				sdl.RenderFillRect(renderer, &sdl.FRect{f32(cmd.rect.x),f32(cmd.rect.y),f32(cmd.rect.w),f32(cmd.rect.h)})
			case ^ui.Command_Icon:
			case ^ui.Command_Clip:
			case ^ui.Command_Jump:
			}
		}

		// free context.temp_allocator from use of fmt.ctprint
		free_all(context.temp_allocator)

		// Present renderer
		sdl.RenderPresent(renderer)
		sdl.PumpEvents()

		// Get counter after whole frame
		frame_end := sdl.GetTicksNS()
		delta:= frame_end - frame_start

		// Cap fps if enabled
		npf_target := u64(1000000000 / fps_target) // nanoseconds per frame target
		if fps_cap_enabled && (delta) < npf_target {
			sleep_time := npf_target - delta
			sdl.DelayPrecise(sleep_time)
			frame_end = sdl.GetTicksNS() // Update frame_end counter to include sleep_time for fps calculation
		}

		// update fps tracker
		fps = 1000000000.000 / f64(delta)
		delta = frame_end - frame_start
		if(!state.timerRunning) { continue }

		state.nanoseconds += f32(delta)
		if(state.nanoseconds >= 1000000000){
			if(state.seconds - 1 < 0){
				if(state.minute-1 < 0){
					if(state.hour-1 < 0){
						queue.push_back(&imageQueue, nextImage(&imageIndex, len(dyn_arr)))
					}else{
						state.hour   -=  1
						state.minute += 60
					}
				}else{
					state.minute -=  1
					state.seconds+= 60
				}
			}
			state.seconds -= 1
			state.nanoseconds -= 1000000000
		}

	}
}
