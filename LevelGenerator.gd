extends Node3D


var map_save_folder: String

# The amount of blocks that make up a level
var level_width : int = 32
var level_height : int = 32

@export var level_manager : Node3D
@export var chunkScene: PackedScene = null
@export_file var default_level_json


# Parameters for dynamic chunk loading
var creation_radius = 2
var survival_radius = 3
var loaded_chunks = {} # Dictionary to store loaded chunks with their positions as keys
var player_position = Vector2.ZERO # Player's position, updated regularly


var loading_thread: Thread
var loading_semaphore: Semaphore
var thread_mutex: Mutex
var should_stop: bool = false


# Called when the node enters the scene tree for the first time.
func _ready():
	initialize_map_data()
	
	#Example pseudo-logic for loading
	#var chunks_to_load = calculate_chunks_to_load(Vector2(0,0))
	#for chunk_pos in chunks_to_load:
		#load_chunk(chunk_pos)
	thread_mutex = Mutex.new()
	loading_thread = Thread.new()
	loading_semaphore = Semaphore.new()
	loading_thread.start(_chunk_management_logic)
	#$"../NavigationRegion3D".bake_navigation_mesh()
	## Start a loop to update chunks based on player position
	set_process(true)
	start_timer()


# Function to create and start a timer that will generate chunks every 1 second if applicable
func start_timer():
	var my_timer = Timer.new() # Create a new Timer instance
	my_timer.wait_time = 1 # Timer will tick every 1 second
	my_timer.one_shot = false # False means the timer will repeat
	add_child(my_timer) # Add the Timer to the scene as a child of this node
	my_timer.timeout.connect(_on_Timer_timeout) # Connect the timeout signal
	my_timer.start() # Start the timer


# This function will be called every time the Timer ticks
func _on_Timer_timeout():
	var player = get_tree().get_first_node_in_group("Players")
	var new_position = Vector2(player.global_transform.origin.x, player.global_transform.origin.z) / Vector2(level_width, level_height)
	#var chance = randi_range(0, 100)
	if new_position != player_position:# and chance < 1:
		thread_mutex.lock()
		#should_stop = false
		player_position = new_position
		#_chunk_management_logic()
		thread_mutex.unlock()
		loading_semaphore.post()  # Signal that there's work to be done


# We store the level map width and height
# If the map has been previously saved, load the saved chunks into memory
func initialize_map_data():
	map_save_folder = Helper.save_helper.get_saved_map_folder(Helper.current_level_pos)
	var level_name: String = Helper.current_level_name
	var tacticalMapJSON: Dictionary = {}
	if map_save_folder == "":
		tacticalMapJSON = Helper.json_helper.load_json_dictionary_file(\
		Gamedata.data.tacticalmaps.dataPath + level_name)
		Helper.loaded_chunk_data.mapheight = tacticalMapJSON.mapheight
		Helper.loaded_chunk_data.mapwidth = tacticalMapJSON.mapwidth
	else:
		tacticalMapJSON = Helper.json_helper.load_json_dictionary_file(\
		map_save_folder + "/map.json")
		Helper.loaded_chunk_data = tacticalMapJSON
		#for chunk in tacticalMapJSON.chunks:
			#Helper.loaded_chunk_data.chunks[Vector2(chunk.chunk_x, chunk.chunk_z)] = chunk


# Called when no data has been put into memory yet in loaded_chunk_data
# Will get the chunk data from map json definition to create a brand new chunk
func get_chunk_data_at_position(mypos: Vector2) -> Dictionary:
	var tacticalMapJSON = Helper.json_helper.load_json_dictionary_file(\
		Gamedata.data.tacticalmaps.dataPath + Helper.current_level_name)
	var y: int = int(mypos.y)
	var x: int = int(mypos.x)
	var index: int = y * Helper.loaded_chunk_data.mapwidth + x
	if index >= 0 and index < (Helper.loaded_chunk_data.mapwidth*Helper.loaded_chunk_data.mapheight):
		return tacticalMapJSON.chunks[index]
	else:
		print("Position out of bounds or invalid index.")
		return {}

#
## Update the player position and update chunks using loading_semaphore.post()
#func _process(_delta):
	#var player = get_tree().get_first_node_in_group("Players")
	#var new_position = Vector2(player.global_transform.origin.x, player.global_transform.origin.z) / Vector2(level_width, level_height)
	#var chance = randi_range(0, 100)
	#if new_position != player_position and chance < 1:
		#thread_mutex.lock()
		#should_stop = false
		#player_position = new_position
		#_chunk_management_logic()
		#thread_mutex.unlock()
		#loading_semaphore.post()  # Signal that there's work to be done
#

func _exit_tree():
	thread_mutex.lock()
	should_stop = true
	thread_mutex.unlock()
	loading_semaphore.post()  # Ensure the thread exits wait state
	loading_thread.wait_to_finish()


func _chunk_management_logic():
	while not should_stop:
		loading_semaphore.wait()  # Wait for signal
		if should_stop: break  # Check if should stop after waking up

		thread_mutex.lock()
		var current_player_chunk = player_position.floor()

		#Example pseudo-logic for loading
		var chunks_to_load = calculate_chunks_to_load(current_player_chunk)
		for chunk_pos in chunks_to_load:
			load_chunk(chunk_pos)

		##And for unloading
		var chunks_to_unload = calculate_chunks_to_unload(current_player_chunk)
		for chunk_pos in chunks_to_unload:
			call_deferred("unload_chunk", chunk_pos)

		#should_stop = true
		thread_mutex.unlock()
		#if chunks_to_load.size() > 0:
			#$"../NavigationRegion3D".bake_navigation_mesh()
		OS.delay_msec(100)  # Optional: delay to reduce CPU usage


func calculate_chunks_to_load(player_chunk_pos: Vector2) -> Array:
	var chunks_to_load = []
	for x in range(player_chunk_pos.x - creation_radius, player_chunk_pos.x + creation_radius + 1):
		for y in range(player_chunk_pos.y - creation_radius, player_chunk_pos.y + creation_radius + 1):
			var chunk_pos = Vector2(x, y)
			# Check if chunk_pos is within the map dimensions
			if is_pos_in_map(x,y) and not loaded_chunks.has(chunk_pos):
				chunks_to_load.append(chunk_pos)
	return chunks_to_load


# Returns if the provided position falls within the tacticalmap dimensions
func is_pos_in_map(x, y) -> bool:
	return x >= 0 and x < Helper.loaded_chunk_data.mapwidth and y >= 0 and y < Helper.loaded_chunk_data.mapheight


# Returns chunks that are loaded but outside of the survival radius
func calculate_chunks_to_unload(player_chunk_pos: Vector2) -> Array:
	var chunks_to_unload = []
	for chunk_pos in loaded_chunks.keys():
		if chunk_pos.distance_to(player_chunk_pos) > survival_radius:
			chunks_to_unload.append(chunk_pos)
	return chunks_to_unload


# Loads a chunk into existence. If it has been previously loaded, we get the data from loaded_chunk_data
# If it has not been previously loaded, we get it from the map json definition
func load_chunk(chunk_pos: Vector2):
	var newChunk = Chunk.new()#chunkScene.instantiate()
	newChunk.mypos = Vector3(chunk_pos.x * level_width, 0, chunk_pos.y * level_height)
	if Helper.loaded_chunk_data.chunks.has(chunk_pos):
		newChunk.chunk_data = Helper.loaded_chunk_data.chunks[chunk_pos]
		#newChunk.generate_saved_chunk(loaded_chunk_data[chunk_pos])
	else:
		# This chunk has not been loaded before, so we need to use the chunk data definition instead
		newChunk.chunk_data = get_chunk_data_at_position(chunk_pos)
		#newChunk.generate_new_chunk(get_chunk_data_at_position(chunk_pos))
	#newChunk.generate()
	level_manager.add_child.call_deferred(newChunk)
	#newChunk.global_position = Vector3(chunk_pos.x * level_width, 0, chunk_pos.y * level_height)
	# Additional logic to initialize chunk...
	loaded_chunks[chunk_pos] = newChunk
	# If the chunk has been loaded before, we use that data


func unload_chunk(chunk_pos: Vector2):
	if loaded_chunks.has(chunk_pos):
		var chunk = loaded_chunks[chunk_pos]
		Helper.loaded_chunk_data.chunks[chunk_pos] = chunk.get_chunk_data()
		chunk.queue_free() # Or any other cleanup logic
		loaded_chunks.erase(chunk_pos)
