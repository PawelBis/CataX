extends Panel

@export var item_button_container : VBoxContainer
@export var item_craft_button : PackedScene

@export var description : Label
@export var required_items : VBoxContainer
@export var recipeVBoxContainer : VBoxContainer

@export var start_crafting_button : Button

@export var hud : NodePath

signal start_craft(item: Dictionary, recipe: Dictionary)


var active_recipe: Dictionary # The currently selected recipe
var active_item: Dictionary # THe currently selected item in the itemlist
# Dictionary to store buttons with item IDs as keys
var item_buttons = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	start_craft.connect(ItemManager.on_crafting_menu_start_craft)
	ItemManager.allAccessibleItems_changed.connect(_on_allAccessibleItems_changed)
	create_item_buttons()


# Function to create item buttons based on craftable items
func create_item_buttons():
	for item in CraftingRecipesManager.craftable_items:
		create_item_button(item)


# Updated function to store button references
func create_item_button(item: Dictionary):
	var button = Button.new()
	var button_icon = Gamedata.get_sprite_by_id(Gamedata.data.items, item.get("id"))
	if button_icon:
		button.icon = button_icon
	button.text = item["name"]
	button.button_up.connect(_on_item_button_clicked.bind(item))

	# Initially set the button color based on craftability
	update_button_color(button, item)

	item_button_container.add_child(button)
	# Store the button reference keyed by item's ID
	item_buttons[item.get("id")] = button


# Function to update a button's color based on the item's craftability
func update_button_color(button, item):
	if can_craft_any_recipe(item):
		button.modulate = Color(0.4, 1, 0.4)  # Green for craftable
	else:
		button.modulate = Color(1, 0.4, 0.4)  # Red for not craftable


# The user has clicked on one of the item buttons in the itemlist
# Update the list of recipes for this item
func _on_item_button_clicked(item: Dictionary):
	active_item = item
	description.text = item["description"]  # Set the description label
	var recipes = item.get("Craft",[])             # Get the recipe array from the item
	for element in recipeVBoxContainer.get_children():
		recipeVBoxContainer.remove_child(element)
		element.queue_free()  # Properly free the node to avoid memory leaks

	for i in range(recipes.size()):
		var recipe_button = Button.new()
		recipe_button.text = "Recipe %d" % (i + 1)
		recipeVBoxContainer.add_child(recipe_button)
		recipe_button.button_up.connect(_on_recipe_button_pressed.bind(recipes[i]))

	if recipes.size() > 0:
		_on_recipe_button_pressed(recipes[0])  # Automatically select the first recipe


# When a recipe button is pressed, update the required items label
func _on_recipe_button_pressed(recipe):
	active_recipe = recipe
	for element in required_items.get_children():
		required_items.remove_child(element)
		element.queue_free()  # Properly free the node to avoid memory leaks

	for resource in recipe.get("required_resources", []):
		var item_id = resource["id"]
		var amount = resource["amount"]
		var resource_container = HBoxContainer.new()
		var item_data = Gamedata.get_data_by_id(Gamedata.data.items,item_id)
		var item_name: String = item_data["name"]
		required_items.add_child(resource_container)

		var item_icon_texture = Gamedata.get_sprite_by_id(Gamedata.data.items, item_id)
		if item_icon_texture:
			var icon = TextureRect.new()
			icon.texture = item_icon_texture
			icon.custom_minimum_size = Vector2(32, 32)  # Set a fixed size for icons
			resource_container.add_child(icon)

		var label = Label.new()
		label.text = " %s: %d" % [item_name, amount]
		resource_container.add_child(label)


func _on_start_crafting_button_pressed():
	start_craft.emit(active_item, active_recipe)


# Function to determine if any of the item's recipes can be crafted
func can_craft_any_recipe(item_data: Dictionary) -> bool:
	# Check if the item data has the 'Craft' property
	if "Craft" in item_data:
		# Iterate over each recipe in the 'Craft' property
		for recipe in item_data["Craft"]:
			# Call the CraftingRecipesManager to check if the recipe can be crafted
			if CraftingRecipesManager.can_craft_recipe(recipe):
				return true  # Return true if any recipe can be crafted
	# Return false if no recipes can be crafted or if there are no recipes
	return false


# Function to update the color of the button associated with a given item data
func update_item_button_color(item_data: Dictionary) -> void:
	var item_id = item_data.get("id")
	if item_id in item_buttons:
		var button = item_buttons[item_id]
		update_button_color(button, item_data)


# Some inventory item has been moved or changed. Now we want to update the UI so that
# the player knows what items can be crafted based on the new inventory contents
# We could update all of the recipes, but we only need to update recipes that
# reference the item that was added/moved/removed. Therefore,
# - We get the item references from the inventory item
# - For each item reference, update the button that represents the item in the ui
func _update_button_from_inventory_item(item: InventoryItem) -> void:
	var item_id = item.get("prototype_id")
	var item_data: Dictionary = Gamedata.get_data_by_id(Gamedata.data.items, item_id)
	var item_references = Helper.json_helper.get_nested_data(item_data,"references.core.items")
	if item_references:
		for item_reference: String in item_references:
			var item_reference_data = Gamedata.get_data_by_id(Gamedata.data.items, item_reference)
			update_item_button_color(item_reference_data)


func _on_allAccessibleItems_changed(items_added: Array, items_removed: Array):
	# Update buttons for items that were added
	for item in items_added:
		_update_button_from_inventory_item(item)

	# Update buttons for items that were removed
	for item in items_removed:
		_update_button_from_inventory_item(item)
