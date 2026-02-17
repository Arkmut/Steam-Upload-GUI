extends PanelContainer

const ENCRYPT_PW : String		= "STEAMUPLOADGUI"
const SETTINGS_FILE : String	= "/SteamUploadGUI_settings.bin"
const STEAMCMD : String			= "steamcmd.exe"
const GODOT_BAT : String		= "godot_exec.bat"
const BATCH_CONTENT : String	= "@echo off\nSTART cmd {mode} \"\"{path}steamcmd.exe\" {args}\""
const STEAM_GUARD : String		= "cd {path} && {steam_cmd} \"set_steam_guard_code {guard_code}\""
const TEXT_WAIT_CLOSE : String	= "Please close Steam shell when it is done to continue.\nUploading App ID '%s'"
const TEXT_WAIT : String		= "Waiting for Content Builder and Upload.\nUploading App ID '%s'"
const APP_GROUP : PackedScene	= preload("res://AppGroup.tscn")
const USER_PANEL : PackedScene	= preload("res://UserPanel.tscn")
var local_dir : String			= ""
var contentbuilder_dir : String = ""
var scripts_path : String		= ""
var builder_path : String		= ""
var steam_apps : Array			= []
var users : Dictionary			= {}

var regex_appid : RegEx		= RegEx.new()
var regex_descr : RegEx		= RegEx.new()


func _ready() -> void:
	regex_appid.compile("\"appid\".\"(.*)\"")
	regex_descr.compile("\"desc\".\"(.*)\"")
	
	local_dir = ProjectSettings.globalize_path("res://")
	if local_dir == "":
		local_dir = OS.get_executable_path().get_base_dir()
	else:
		local_dir = local_dir.get_base_dir()
	contentbuilder_dir = local_dir
	
	# Load local Settings saved from last Upload
	var loaded_file_content := {}
	if FileAccess.file_exists(local_dir + SETTINGS_FILE):
		var file:=FileAccess.open_encrypted_with_pass(local_dir + SETTINGS_FILE, FileAccess.READ, ENCRYPT_PW)
		var settings_json_result := JSON.new()
		settings_json_result.parse(file.get_as_text())
		
		if settings_json_result.data:
			users = settings_json_result.data.users
			contentbuilder_dir = settings_json_result.data.path
		file.close()
	for u in users.keys():
		if not users[u].has("save_pw") or not users[u].has("pw") or not users[u].has("username"):
			users.erase(u)
	update_users()
	$"%ContentBuilderPathEdit".text = contentbuilder_dir
	if check_contentbuilder_path():
		generate_apps_from_vdfs()


func clear_apps():
	# Clear old list of Steam apps...
	if not steam_apps.is_empty():
		for steam_app in steam_apps:
			steam_app.queue_free()
		steam_apps.clear()


func generate_apps_from_vdfs():
	clear_apps()
	scripts_path = contentbuilder_dir + "/scripts/"
	# Get all the files located in the /scripts/ folder
	if DirAccess.dir_exists_absolute(scripts_path):
		$"%AppsErrorMessage".hide()
		$"%AppsErrorOpenDirButton".hide()
		var files : Array = list_vdf_files_in_directory(scripts_path)
		for file_name in files:
			if not FileAccess.file_exists(scripts_path + file_name):
				continue
			var file:=FileAccess.open(scripts_path + file_name, FileAccess.READ)
			var file_content : String = file.get_as_text()
			file_content = file_content.to_lower()
			file.close()
			if file_content.left(10) != "\"appbuild\"":
				# The file is not a "app" vdf, only a depot vdf
				continue
			
			# Create the App Group elements
			var new_app_group : AppGroup = APP_GROUP.instantiate()
			new_app_group.setup(get_appid(file_content), get_desc(file_content), file_name)
			$"%AppsToUpload".add_child(new_app_group)
			$"%SelectedAppsCheckBox".button_pressed = true
			steam_apps.append(new_app_group)
	else:
		$"%AppsErrorMessage".show()
		$"%AppsErrorOpenDirButton".show()


func check_contentbuilder_path() -> bool:
	builder_path = contentbuilder_dir + "/builder/"
	if !DirAccess.dir_exists_absolute(builder_path):
		clear_apps()
		$"%SettingsCheckBox".button_pressed = true
		$"%AppsErrorMessage".show()
		$"%AppsErrorOpenDirButton".show()
		$"%UploadButton".text = "Builder path not found (\"tools\\ContentBuilder\\builder\\\")!"
		$"%UploadButton".disabled = true
		return false
	else:
		if !FileAccess.file_exists(builder_path + STEAMCMD):
			$"%AppsErrorMessage".show()
			$"%AppsErrorOpenDirButton".show()
			$"%UploadButton".text = "steamcmd.exe not found (\"tools\\ContentBuilder\\builder\\steamcmd.exe\")!"
			$"%UploadButton".disabled = true
			return false
		else:
			$"%UploadButton".text = "Upload"
			$"%UploadButton".disabled = false
			return true


func get_appid(_string:String) -> String:
	var s_id_r : RegExMatch = regex_appid.search(_string)
	if s_id_r:
		return s_id_r.get_string(1)
	return "App ID not found!"


func get_desc(_string:String) -> String:
	var s_desc_r : RegExMatch = regex_descr.search(_string)
	if s_desc_r:
		return s_desc_r.get_string(1)
	return "Desc not found!"


func list_vdf_files_in_directory(path:String) -> Array:
	var files = []
	var dir = DirAccess.open(path)
	dir.include_hidden = true
	dir.list_dir_begin()
	
	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with(".") and file.ends_with(".vdf"):
			files.append(file)
	
	dir.list_dir_end()
	return files


func save_settings() -> void:
	# Save the Settings
	var save_pw_file := FileAccess.open_encrypted_with_pass(local_dir + SETTINGS_FILE, FileAccess.WRITE, ENCRYPT_PW)
	var settings_dict := {
		"path" : $"%ContentBuilderPathEdit".text,
		"users" : users
		}
	save_pw_file.store_string(JSON.stringify(settings_dict))
	save_pw_file.close()


func _on_UploadButton_pressed() -> void:
	save_settings()
	
	var selected_user := get_selected_user_credentials()
	
	if selected_user.pw == "":
		var passwordTween := get_tree().create_tween()
		# 1. Shake Sequence (Moves the X position)
		passwordTween.tween_property($"%PasswordMissing", "position:x", 5.0, 0.05)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		passwordTween.tween_property($"%PasswordMissing", "position:x", -5.0, 0.1)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		passwordTween.tween_property($"%PasswordMissing", "position:x", 0.0, 0.05)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		# 2. Fade Sequence (Runs simultaneously with the shake)
		# Using .parallel() makes the next tween start at the same time as the previous one
		passwordTween.parallel().tween_property($"%PasswordMissing", "modulate:a", 1.0, 0.05)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		passwordTween.tween_property($"%PasswordMissing", "modulate:a", 0.5, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		return
	
	# Create an array of the selected vdfs
	# Update the desc content of the vdfs
	var selected_vdfs : Array = []
	for app in steam_apps:
		if app.is_selected() and app.visible:
			selected_vdfs.append({"file": app.vdf_file_name, "app_id": app.app_id})
			var vdf_file := FileAccess.open(scripts_path + app.vdf_file_name, FileAccess.READ)
			var vdf_content : String = vdf_file.get_as_text()
			vdf_file.close()
			var as_lines : PackedStringArray = vdf_content.split("\n")
			for i in as_lines.size():
				if as_lines[i].strip_edges().begins_with("\"desc\""):
					as_lines[i] = as_lines[i].split("\"desc\"")[0] + ("\"desc\" \"%s\"" % app.desc)
					break
			var vdf_write_file := FileAccess.open(scripts_path + app.vdf_file_name, FileAccess.WRITE)
			vdf_write_file.store_string("\n".join(as_lines))
			vdf_write_file.close()
	
	# Upload each App from the selected vdfs
	# A batch file is generated for every upload. This is a workaround of the problem
	# That 'blocking' on OS.execute() while showing the shell will lead to an empty
	# shell window as the stdout is consumed.
	for upload in selected_vdfs:
		var vdf_path = "\"../scripts/%s\"" % upload.file
		var args := ["+login", selected_user.username, selected_user.pw, "+run_app_build", vdf_path, "+quit"]
		var shell_mode : String = "/k" if $"%KeepShellOpen".button_pressed else "/c"
		# Open the Popup informing the user that this is paused until the shells are closed
		$"%SteamUploadingPopup".popup()
		$"%SteamUploadLabel".text = TEXT_WAIT_CLOSE % upload.app_id if $"%KeepShellOpen".button_pressed else TEXT_WAIT % upload.app_id
		await get_tree().process_frame
		var bat_file := FileAccess.open(local_dir + "/godot_exec.bat", FileAccess.WRITE)
		bat_file.store_string(BATCH_CONTENT.format({"mode": shell_mode, "path": builder_path, "args": " ".join(args)}))
		bat_file.close()
		OS.execute(local_dir + "/godot_exec.bat", [], [],true)
	
	await get_tree().process_frame
	DirAccess.open(local_dir).remove("godot_exec.bat")
	$"%SteamUploadingPopup".hide()


func _on_SetSteamGuardButton_pressed():
	$"%SteamGuardPopup".popup_centered(Vector2.ONE)
	$"%SteamGuardCodeEdit".grab_focus()


func _on_SendSteamGuardButton_pressed():
	var cmd_arg = STEAM_GUARD.format({"path": builder_path, "steam_cmd": STEAMCMD, "guard_code": $"%SteamGuardCodeEdit".text, })
	OS.execute("cmd", ["/c", cmd_arg], [],false, true)
	$"%SteamGuardPopup".hide()


func _on_SteamGuardCodeEdit_text_changed(new_text:String) -> void:
	$"%SendSteamGuardButton".disabled = new_text.length() < 5


func _on_ContentBuilderPathEdit_text_entered(new_text:String) -> void:
	contentbuilder_dir = new_text.trim_suffix("\\")
	if check_contentbuilder_path():
		generate_apps_from_vdfs()


func _on_OpenDirButton_pressed():
	$PopupLayer/FileDialog.popup_centered()


func _on_FileDialog_dir_selected(dir):
	_on_ContentBuilderPathEdit_text_entered(dir)
	$"%ContentBuilderPathEdit".text = contentbuilder_dir


func _on_RefreshButton_pressed():
	generate_apps_from_vdfs()


func _on_popup_about_to_show():
	$PopupLayer/UserDialogBG.show()


func _on_popup_hide():
	$PopupLayer/UserDialogBG.hide()


func _on_GitHubLinkButton_pressed():
	OS.shell_open("https://github.com/RPicster/Steam-Upload-GUI")


func _on_CoffeeLinkButton_pressed():
	OS.shell_open("https://www.buymeacoffee.com/raffa")


func _on_SelectedAppsCheckBox_toggled(button_pressed):
	for a in steam_apps:
		a.set_selected(button_pressed)


func _on_AppFilter_text_changed(filter):
	if filter == "":
		$"%SelectedAppsCheckBox".button_pressed = true
		for a in steam_apps:
			a.show()
	else:
		for a in steam_apps:
			a.visible = a.has_filter_name(filter)
			a.set_selected(a.visible)


func _on_SettingsCheckBox_toggled(button_pressed):
	$"%SettingsGroup".visible = button_pressed


func _on_ManageUsersButton_pressed():
	$PopupLayer/UserDialogBG.show()
	$"%UserDialog".popup_centered()


func update_users(and_selection:=true):
	for c in $"%UserList".get_children():
		c.queue_free()
	if and_selection:
		$"%UserSelectionButton".clear()
	if users.is_empty():
		$"%UsersHbox".hide()
		$"%AddUsersButton".show()
		return
	$"%UsersHbox".show()
	$"%AddUsersButton".hide()
	for u in users.keys():
		var new_user : UserPanel = USER_PANEL.instantiate()
		new_user.username = u
		new_user.save_pw = users[u].save_pw
		$"%UserList".add_child(new_user)
		if and_selection:
			$"%UserSelectionButton".add_item(u)
		new_user.delete_user.connect(func(): on_delete_user(u))
		new_user.save_password.connect(func(toggled): on_save_password(u,toggled))
	if and_selection:
		$"%UserSelectionButton".select(0)
		_on_UserSelectionButton_item_selected(0)


func on_add_user():
	var new_user : Dictionary = create_user_dict($"%AddUserNameLineEdit".text)
	users[$"%AddUserNameLineEdit".text] = new_user
	$"%AddUserNameLineEdit".text = ""
	update_users()


func create_user_dict(username:String) -> Dictionary:
	return {"username" : username, "save_pw" : true, "pw": ""}


func on_delete_user(username:String):
	if users.has(username):
		users.erase(username)
	update_users()


func on_save_password(save_pw:bool, username:String):
	if users.has(username):
		users[username].save_pw = save_pw
	update_users(false)


func _on_CloseUserManagementButton_pressed():
	$"%UserDialog".hide()
	$PopupLayer/UserDialogBG.hide()
	update_users()


func _on_SavePW_pressed():
	var selected_user : String = $"%UserSelectionButton".get_item_text($"%UserSelectionButton".get_selected_id())
	if users.has(selected_user):
		users[selected_user].save_pw = $"%SavePW".button_pressed
	update_users(false)


func get_selected_user_credentials() -> Dictionary:
	var username : String = $"%UserSelectionButton".get_item_text($"%UserSelectionButton".get_selected_id())
	var current_user := {"username":username, "pw":""}
	if users.has(username):
		current_user.pw = users[username].pw
	return current_user


func _on_UserSelectionButton_item_selected(index):
	var selected_user : String = $"%UserSelectionButton".get_item_text(index)
	if users.has(selected_user):
		$"%SavePW".button_pressed = users[selected_user].save_pw
		if users[selected_user].save_pw:
			$"%UserPasswordEdit".text = users[selected_user].pw
		else:
			$"%UserPasswordEdit".text = ""
		$"%PasswordMissing".visible = $"%UserPasswordEdit".text == ""


func _on_UserPasswordEdit_text_changed(new_text):
	var selected_user : String = $"%UserSelectionButton".get_item_text($"%UserSelectionButton".get_selected_id())
	if users.has(selected_user) and users[selected_user].save_pw:
		users[selected_user].pw = $"%UserPasswordEdit".text
		$"%PasswordMissing".visible = $"%UserPasswordEdit".text == ""


func _on_SaveSettingsButton_pressed():
	save_settings()
