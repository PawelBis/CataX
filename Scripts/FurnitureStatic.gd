class_name FurnitureStatic
extends StaticBody3D

# This is a standalone script that is not attached to any node. 
# This is the static version of furniture. There is also FurniturePhysics.gd.
# This class is instanced by Chunk.gd when a map needs static furniture, like a bed or fridge


# Since we can't access the scene tree in a thread, we store the position in a variable and read that
var furnitureposition: Vector3
var furniturerotation: int
var furnitureJSON: Dictionary # The json that defines this furniture on the map
var furnitureJSONData: Dictionary # The json that defines this furniture's basics in general
var sprite: Sprite3D = null
var collider: CollisionShape3D = null
var is_door: bool = false
var door_state: String = "Closed"  # Default state

var corpse_scene: PackedScene = preload("res://Defaults/Mobs/mob_corpse.tscn")
var current_health: float = 100.0


func _ready():
	position = furnitureposition
	set_new_rotation(furniturerotation)
	var new_chunk = Helper.map_manager.get_chunk_from_position(furnitureposition)
	new_chunk.add_furniture_to_chunk(self)
	check_door_functionality()
	update_door_visuals()
	# Add the container as a child on the same position as this furniture
	add_container(Vector3(0,0,0))


# Check if this furniture acts as a door
# We check if the door data for this unique furniture has been set
# Otherwise we check the general json data for this furniture
func check_door_functionality():
	if furnitureJSON.get("Function", {}).get("door") or furnitureJSONData.get("Function", {}).get("door"):
		is_door = true
		door_state = furnitureJSON.get("Function", {}).get("door", "Closed")

func interact():
	if is_door:
		toggle_door()


# We set the door property in furnitureJSON, which holds the data
# For this unique furniture
func toggle_door():
	door_state = "Open" if door_state == "Closed" else "Closed"
	furnitureJSON["Function"] = {"door": door_state}
	update_door_visuals()


func get_hit(damage):
	current_health -= damage
	if current_health <= 0:
		_die()


func _die():
	add_corpse.call_deferred(global_position)
	queue_free()




# Will update the sprite of this furniture and set a collisionshape based on it's size
func set_sprite(newSprite: Texture):
	if not sprite:
		sprite = Sprite3D.new()
		add_child.call_deferred(sprite)
	var uniqueTexture = newSprite.duplicate(true) # Duplicate the texture
	sprite.texture = uniqueTexture

	# Calculate new dimensions for the collision shape
	var sprite_width = newSprite.get_width()
	var sprite_height = newSprite.get_height()

	var new_x = sprite_width / 100.0 # 0.1 units per 10 pixels in width
	var new_z = sprite_height / 100.0 # 0.1 units per 10 pixels in height
	var new_y = 0.8 # Any lower will make the player's bullet fly over it

	# Update the collision shape
	var new_shape = BoxShape3D.new()
	new_shape.extents = Vector3(new_x / 2.0, new_y / 2.0, new_z / 2.0) # BoxShape3D extents are half extents

	collider = CollisionShape3D.new()
	collider.shape = new_shape
	add_child.call_deferred(collider)


func update_door_visuals():
	if not is_door: return
	
	var angle = 90 if door_state == "Open" else 0
	var position_offset = Vector3(-0.5, 0, -0.5) if door_state == "Open" else Vector3.ZERO
	apply_transform_to_sprite_and_collider(angle, position_offset)


func apply_transform_to_sprite_and_collider(rotationdegrees, position_offset):
	var doortransform = Transform3D().rotated(Vector3.UP, deg_to_rad(rotationdegrees))
	doortransform.origin = position_offset
	sprite.set_transform(doortransform)
	collider.set_transform(doortransform)
	sprite.rotation_degrees.x = 90


# Set the rotation for this furniture. We have to do some minor calculations or it will end up wrong
func set_new_rotation(amount: int):
	var rotation_amount = amount
	if amount == 180:
		rotation_amount = amount - 180
	elif amount == 0:
		rotation_amount = amount + 180
	else:
		rotation_amount = amount

	# Rotate the entire StaticBody3D node, including its children
	rotation_degrees.y = rotation_amount
	sprite.rotation_degrees.x = 90 # Static 90 degrees to point at camera


func get_my_rotation() -> int:
	return furniturerotation


# Function to make it's own shape and texture based on an id and position
# This function is called by a Chunk to construct it's blocks
func construct_self(furniturepos: Vector3, newFurnitureJSON: Dictionary):
	furnitureJSON = newFurnitureJSON
	# Position furniture at the center of the block by default
	furnitureposition = furniturepos
	# Only previously saved furniture will have the global_position_x key. They do not need to be raised
	if not newFurnitureJSON.has("global_position_x"):
		furnitureposition.y += 0.5 # Move the furniture to slightly above the block 
	add_to_group("furniture")

	# Find out if we need to apply edge snapping
	furnitureJSONData = Gamedata.get_data_by_id(Gamedata.data.furniture,furnitureJSON.id)
	var edgeSnappingDirection = furnitureJSONData.get("edgesnapping", "None")

	var furnitureSprite: Texture = Gamedata.get_sprite_by_id(Gamedata.data.furniture,furnitureJSON.id)
	set_sprite(furnitureSprite)
	
	# Calculate the size of the furniture based on the sprite dimensions
	var spriteWidth = furnitureSprite.get_width() / 100.0 # Convert pixels to meters (assuming 100 pixels per meter)
	var spriteDepth = furnitureSprite.get_height() / 100.0 # Convert pixels to meters
	
	var newRot = furnitureJSON.get("rotation", 0)

	# Apply edge snapping if necessary. Previously saved furniture have the global_position_x. 
	# They do not need to apply edge snapping again
	if edgeSnappingDirection != "None" and not newFurnitureJSON.has("global_position_x"):
		furnitureposition = apply_edge_snapping(furnitureposition, edgeSnappingDirection, \
		spriteWidth, spriteDepth, newRot, furniturepos)

	furniturerotation = newRot


# If edge snapping has been set in the furniture editor, we will apply it here.
# The direction refers to the 'backside' of the furniture, which will be facing the edge of the block
# This is needed to put furniture against the wall, or get a fence at the right edge
func apply_edge_snapping(newpos, direction, width, depth, newRot, furniturepos) -> Vector3:
	# Block size, a block is 1x1 meters
	var blockSize = Vector3(1.0, 1.0, 1.0)
	
	# Adjust position based on edgesnapping direction and rotation
	match direction:
		"North":
			newpos.z -= blockSize.z / 2 - depth / 2
		"South":
			newpos.z += blockSize.z / 2 - depth / 2
		"East":
			newpos.x += blockSize.x / 2 - width / 2
		"West":
			newpos.x -= blockSize.x / 2 - width / 2
		# Add more cases if needed
	
	# Consider rotation if necessary
	newpos = rotate_position_around_block_center(newpos, newRot, furniturepos)
	
	return newpos


# Called when applying edge-snapping so it's put into the right position
func rotate_position_around_block_center(newpos, newRot, block_center) -> Vector3:
	# Convert rotation to radians for trigonometric functions
	var radians = deg_to_rad(newRot)
	
	# Calculate the offset from the block center
	var offset = newpos - block_center
	
	# Apply rotation matrix transformation
	var rotated_offset = Vector3(
		offset.x * cos(radians) - offset.z * sin(radians),
		offset.y,
		offset.x * sin(radians) + offset.z * cos(radians)
	)
	
	# Return the new position
	return block_center + rotated_offset


# Returns this furniture's data for saving
func get_data() -> Dictionary:
	var newfurniturejson = {
		"id": furnitureJSON.id,
		"moveable": false,
		"global_position_x": furnitureposition.x,
		"global_position_y": furnitureposition.y,
		"global_position_z": furnitureposition.z,
		"rotation": get_my_rotation(),
	}
	
	if "Function" in furnitureJSONData and "door" in furnitureJSONData.Function:
		newfurniturejson["Function"] = {"door": door_state}
	return newfurniturejson


# When the furniture is destroyed, it leaves a wreck behind
func add_corpse(pos: Vector3):
	var newItem: ContainerItem = ContainerItem.new()
	
	# TODO: Implement furniture wreck loot group and wreck property for furniture
	newItem.itemgroup = "mob_loot"
	
	newItem.add_to_group("mapitems")
	newItem.construct_self(pos)
	# Finally add the new item with possibly set loot group to the tree
	get_tree().get_root().add_child.call_deferred(newItem)


# If this furniture is a container, it will add a container node to the furniture
# If there is an itemgroup assigned to the furniture, it will be added to the container
# Which will fill up the container with items from the itemgroup
func add_container(pos: Vector3):
	# Check if the furnitureJSONData has 'Function' and if 'Function' has 'container'
	if "Function" in furnitureJSONData and "container" in furnitureJSONData["Function"]:
		var newItem: ContainerItem = ContainerItem.new()
		
		# Check if the container has an 'itemgroup'
		if "itemgroup" in furnitureJSONData["Function"]["container"]:
			newItem.itemgroup = furnitureJSONData["Function"]["container"]["itemgroup"]
		else:
			# The furniture is a container, but no items are in it. We still create an empty container
			print_debug("No itemgroup found for container in furniture ID: " + str(furnitureJSONData["id"]))

		newItem.construct_self(pos)
		# Add the new item with possibly set itemgroup as a child.
		add_child.call_deferred(newItem)
	else:
		print_debug("Function or container property not found in furniture JSON Data for ID: " + str(furnitureJSONData["id"]))
