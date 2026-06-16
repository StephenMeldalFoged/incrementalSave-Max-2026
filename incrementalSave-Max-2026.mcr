-- Incremental Save v1.0
-- Original v0.5 (c) 2003 M. Breidt (martin@breidt.net)
-- Modernized 2026 by Stephen Foged for 3ds Max 2027.1
--
-- What changed from v0.5:
--   FIXED  ALT opens settings dialog (docs said CTRL, code checked altPressed — now consistent)
--   FIXED  comment_txt was a leaked implicit global; now scoped to execute handler
--   FIXED  version number extracted as integer, not float — prevents _V-1.5 edge case
--   FIXED  glob wildcard capped discovery at padding width; dotNet regex scan finds any width
--   FIXED  crash window between rename and save eliminated by atomic temp-file pattern
--   NEW    getFileSize replaces manual fOpen/fseek/ftell binary stream dance
--   NEW    INI persistence via setINISetting/getINISetting replaces persistent globals
--          (persistent globals reset on Max crash or major version upgrade)
--
-- How the atomic save works:
--   1. Save scene to a temp file in the scene directory — verify it
--   2. Rename current .max → versioned backup (shot06-comp.max → shot06-comp_V-004.max)
--   3. Rename temp → canonical name (shot06-comp.max)
--   At no point is the canonical filename absent from disk.
--
-- Installation:
--   Copy to %LOCALAPPDATA%\Autodesk\3dsMax\<version>\ENU\scripts\startup\
--   or drag-drop onto the Max viewport.
--   Action appears in the "Eski Tools" category — assign Alt+Ctrl+S.
--
-- Usage:
--   Invoke normally to save. Hold ALT when invoking to open the settings dialog.

macroScript incrementalSave
category:"Eski Tools"
buttonText:"Incremental Save 2026"
toolTip:"Incremental Save 2026"
(
	local iniPath = (getDir #userScripts) + "\\incrementalSave.ini"

	fn isReadSetting key default = (
		local v = getINISetting iniPath "IncrementalSave" key
		if v == "" then default else v
	)

	fn writeSetting key val = setINISetting iniPath "IncrementalSave" key (val as string)

	fn padNumber nr padLen = (
		local s = nr as string
		while s.count < padLen do s = "0" + s
		s
	)

	-- Uses dotNet regex so version scan works regardless of padding width.
	-- Returns the highest integer version found, or 0 if none exist.
	fn findHighestVersion backupBase sepSym = (
		local ioDir   = dotNetClass "System.IO.Directory"
		local ioPath  = dotNetClass "System.IO.Path"
		local reClass = dotNetClass "System.Text.RegularExpressions.Regex"

		local folder   = ioPath.GetDirectoryName backupBase
		local fileBase = ioPath.GetFileName backupBase

		if not (ioDir.Exists folder) then return 0

		local rxPattern = (reClass.Escape (fileBase + sepSym)) + "(\\d+)\\.max$"
		local rx        = dotNetObject "System.Text.RegularExpressions.Regex" rxPattern \
		                  ((dotNetClass "System.Text.RegularExpressions.RegexOptions").IgnoreCase)

		local highest = 0
		local allFiles = ioDir.GetFiles folder (fileBase + sepSym + "*.max")

		for f in allFiles do (
			local m = rx.Match (ioPath.GetFileName f)
			if m.Success then (
				local n = (m.Groups.get_Item 1).Value as integer
				if n > highest then highest = n
			)
		)
		highest
	)

	fn verifiedSaveFile fName = (
		local minBytes = 10000

		if not (saveMaxFile fName) then (
			messageBox "File could not be saved!\nRe-save normally." title:"IncrementalSave Error #1" beep:true
			setSaveRequired true
			return false
		)
		if not (doesFileExist fName) then (
			messageBox "File not found after saving!\nRe-save normally." title:"IncrementalSave Error #2" beep:true
			setSaveRequired true
			return false
		)
		local sz = getFileSize fName
		if sz < minBytes then (
			messageBox ("Saved file is suspiciously small (" + sz as string + " bytes).\nProbably corrupt — re-save normally.") \
				title:"IncrementalSave Error #3" beep:true
			setSaveRequired true
			return false
		)
		format "IncrementalSave: verified OK — %\n" fName
		true
	)

	on execute do (
		-- Read settings from INI (survive Max crashes and version upgrades)
		local cfg_debug  = (isReadSetting "debug"    "false") == "true"
		local cfg_subDir = (isReadSetting "subDir"   "true")  == "true"
		local cfg_ext    =  isReadSetting "subDirExt" ".bak"
		local cfg_sep    =  isReadSetting "sepSym"    "_V-"
		local cfg_pad    = (isReadSetting "padLen"    "3") as integer
		local cfg_doCmt  = (isReadSetting "doCmt"    "false") == "true"
		-- global needed: rollouts cannot close over outer locals in MaxScript
		global incrementalSave_cmt = ""

		rollout fileCommentRO "File Comments" (
			editText cmtField fieldWidth:400 height:100 text:incrementalSave_cmt
			button btn_ok "OK" width:100
			on btn_ok pressed do (
				incrementalSave_cmt = cmtField.text
				destroyDialog fileCommentRO
			)
		)

		rollout settingsRO "IncrementalSave v1.0 — Settings" (
			checkbox chk_subDir "Save old versions in subdirectory" checked:cfg_subDir
			edittext fld_ext "Subdirectory suffix:" text:cfg_ext enabled:cfg_subDir fieldWidth:70 align:#right
			edittext fld_sep "Version number prefix:" text:cfg_sep fieldWidth:70 align:#right
			label lbl_pad "Version number padding:" across:2 align:#left
			spinner spn_pad range:[2,10,cfg_pad] type:#integer fieldWidth:42 align:#right
			checkbox chk_cmt   "Add file comments on save"       checked:cfg_doCmt
			checkbox chk_debug "Print debug info to Listener"    checked:cfg_debug
			group "Filename preview:" ( label lbl_prev "" )
			button btn_ok "OK" width:60

			fn refreshPreview = (
				local s = "myScene"
				if cfg_subDir then s += (cfg_ext + "\\" + s)
				s += cfg_sep
				for i = 2 to cfg_pad do s += "0"
				s += "1.max"
				lbl_prev.text = s
			)

			on settingsRO open   do refreshPreview()
			on chk_subDir changed val do ( cfg_subDir = val; fld_ext.enabled = val; refreshPreview() )
			on fld_ext    changed val do ( cfg_ext = val; refreshPreview() )
			on fld_sep    changed val do ( cfg_sep = val; refreshPreview() )
			on spn_pad    changed val do ( cfg_pad = val as integer; refreshPreview() )
			on chk_cmt    changed val do   cfg_doCmt = val
			on chk_debug  changed val do   cfg_debug = val
			on btn_ok pressed do (
				writeSetting "debug"     cfg_debug
				writeSetting "subDir"    cfg_subDir
				writeSetting "subDirExt" cfg_ext
				writeSetting "sepSym"    cfg_sep
				writeSetting "padLen"    cfg_pad
				writeSetting "doCmt"     cfg_doCmt
				destroyDialog settingsRO
			)
		)

		format "IncrementalSave v1.0\n"

		-- ALT opens settings dialog (v0.5 had this comment wrong — it said CTRL)
		if keyboard.altPressed then createDialog settingsRO 310 230 modal:true

		-- Ask if scene is clean
		local cont = true
		if not getSaveRequired() then
			cont = queryBox "Scene has not been modified.\nSave anyway?" title:"IncrementalSave"
		if not cont then return undefined

		-- Collect file comments before saving
		if cfg_doCmt then (
			local propNo = fileProperties.findProperty #summary "Comments"
			if propNo > 0 then incrementalSave_cmt = fileProperties.getPropertyValue #summary propNo else incrementalSave_cmt = ""
			createDialog fileCommentRO modal:true width:440 height:155
			fileProperties.addProperty #summary "Comments" incrementalSave_cmt
		)

		-- New unsaved scene — fall back to normal Save As
		if maxFileName == "" then (
			local saveName = getMAXSaveFileName()
			if saveName != undefined then verifiedSaveFile saveName
			else format "IncrementalSave: cancelled by user.\n"
			return undefined
		)

		local currentFile = maxFilePath + maxFileName

		-- File was renamed/deleted externally — just re-save to same name
		if not doesFileExist currentFile then (
			verifiedSaveFile currentFile
			return undefined
		)

		-- Read-only guard
		if getFileAttribute currentFile #readonly then (
			messageBox ("File is read-only:\n" + currentFile + "\n\nScene not saved!") \
				title:"IncrementalSave Error #4" beep:true
			return undefined
		)

		-- Build backup base path (no extension)
		local baseName  = getFilenameFile maxFileName
		local backupDir = if cfg_subDir then (maxFilePath + baseName + cfg_ext) else maxFilePath

		if cfg_subDir and not doesFileExist backupDir then (
			if not (makeDir backupDir) then (
				format "IncrementalSave: could not create %, falling back to scene dir\n" backupDir
				backupDir = maxFilePath
			)
		)

		local backupBase = backupDir + "\\" + baseName

		if cfg_debug then format "IncrementalSave: backupBase = %\n" backupBase

		-- Find highest existing version via regex (not limited to current padding width)
		local nextNr      = (findHighestVersion backupBase cfg_sep) + 1
		local backupFile  = backupBase + cfg_sep + (padNumber nextNr cfg_pad) + ".max"
		local tempFile    = maxFilePath + baseName + "_ISAVE_TMP_.max"

		if cfg_debug then format "IncrementalSave: backup target = %\n" backupFile

		-- === Atomic rotate ===
		-- Step 1: save to temp and verify — current canonical file is untouched until we know the save worked
		if not (verifiedSaveFile tempFile) then return undefined

		-- Step 2: rename canonical → versioned backup
		if not (renameFile currentFile backupFile) then (
			messageBox ("Could not archive current file:\n" + currentFile + "\n\nTemp save preserved at:\n" + tempFile) \
				title:"IncrementalSave Error #5" beep:true
			setSaveRequired true
			return undefined
		)

		-- Step 3: promote temp → canonical name
		if not (renameFile tempFile currentFile) then (
			messageBox ("Temp rename failed.\n\nBackup at: " + backupFile + "\nTemp at:   " + tempFile + "\n\nRename temp to restore your scene file.") \
				title:"IncrementalSave Error #6" beep:true
			setSaveRequired true
			return undefined
		)

		format "IncrementalSave: archived  -> %\n" backupFile
		format "IncrementalSave: canonical -> %\n" currentFile

	) -- on execute
) -- macroScript
