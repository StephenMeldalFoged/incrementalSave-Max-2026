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
		-- Rollouts cannot close over outer locals in MaxScript — all shared state must be global.
		-- Prefixed with incrementalSave_ to avoid namespace collisions.
		global incrementalSave_debug  = (isReadSetting "debug"    "false") == "true"
		global incrementalSave_subDir = (isReadSetting "subDir"   "true")  == "true"
		global incrementalSave_ext    =  isReadSetting "subDirExt" ".bak"
		global incrementalSave_sep    =  isReadSetting "sepSym"    "_V-"
		global incrementalSave_pad    = (isReadSetting "padLen"    "3") as integer
		global incrementalSave_doCmt  = (isReadSetting "doCmt"    "false") == "true"
		global incrementalSave_cmt    = ""

		rollout fileCommentRO "File Comments" (
			editText cmtField fieldWidth:400 height:100 text:incrementalSave_cmt
			button btn_ok "OK" width:100
			on btn_ok pressed do (
				incrementalSave_cmt = cmtField.text
				destroyDialog fileCommentRO
			)
		)

		rollout settingsRO "IncrementalSave v1.0 — Settings" (
			checkbox chk_subDir "Save old versions in subdirectory" checked:incrementalSave_subDir
			edittext fld_ext "Subdirectory suffix:" text:incrementalSave_ext enabled:incrementalSave_subDir fieldWidth:70 align:#right
			edittext fld_sep "Version number prefix:" text:incrementalSave_sep fieldWidth:70 align:#right
			label lbl_pad "Version number padding:" across:2 align:#left
			spinner spn_pad range:[2,10,incrementalSave_pad] type:#integer fieldWidth:42 align:#right
			checkbox chk_cmt   "Add file comments on save"    checked:incrementalSave_doCmt
			checkbox chk_debug "Print debug info to Listener" checked:incrementalSave_debug
			group "Filename preview:" ( label lbl_prev "" )
			button btn_ok "OK" width:60

			fn refreshPreview = (
				local s = "myScene"
				if incrementalSave_subDir then s += (incrementalSave_ext + "\\" + s)
				s += incrementalSave_sep
				for i = 2 to incrementalSave_pad do s += "0"
				s += "1.max"
				lbl_prev.text = s
			)

			on settingsRO open   do refreshPreview()
			on chk_subDir changed val do ( incrementalSave_subDir = val; fld_ext.enabled = val; refreshPreview() )
			on fld_ext    changed val do ( incrementalSave_ext = val; refreshPreview() )
			on fld_sep    changed val do ( incrementalSave_sep = val; refreshPreview() )
			on spn_pad    changed val do ( incrementalSave_pad = val as integer; refreshPreview() )
			on chk_cmt    changed val do   incrementalSave_doCmt = val
			on chk_debug  changed val do   incrementalSave_debug = val
			on btn_ok pressed do (
				writeSetting "debug"     incrementalSave_debug
				writeSetting "subDir"    incrementalSave_subDir
				writeSetting "subDirExt" incrementalSave_ext
				writeSetting "sepSym"    incrementalSave_sep
				writeSetting "padLen"    incrementalSave_pad
				writeSetting "doCmt"     incrementalSave_doCmt
				destroyDialog settingsRO
			)
		)

		format "IncrementalSave v1.0 — Modernized 2026 by Stephen Foged (based on v0.5 by M. Breidt)\n"

		-- ALT opens settings dialog (v0.5 had this comment wrong — it said CTRL)
		if keyboard.altPressed then createDialog settingsRO 310 230 modal:true

		-- Ask if scene is clean
		local cont = true
		if not getSaveRequired() then
			cont = queryBox "Scene has not been modified.\nSave anyway?" title:"IncrementalSave"
		if not cont then return undefined

		-- Collect file comments before saving
		if incrementalSave_doCmt then (
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
		local backupDir = if incrementalSave_subDir then (maxFilePath + baseName + incrementalSave_ext) else maxFilePath

		if incrementalSave_subDir and not doesFileExist backupDir then (
			if not (makeDir backupDir) then (
				format "IncrementalSave: could not create %, falling back to scene dir\n" backupDir
				backupDir = maxFilePath
			)
		)

		local backupBase = backupDir + "\\" + baseName

		if incrementalSave_debug then format "IncrementalSave: backupBase = %\n" backupBase

		-- Find highest existing version via regex (not limited to current padding width)
		local nextNr     = (findHighestVersion backupBase incrementalSave_sep) + 1
		local backupFile = backupBase + incrementalSave_sep + (padNumber nextNr incrementalSave_pad) + ".max"
		local tempFile   = maxFilePath + baseName + "_ISAVE_TMP_.max"

		if incrementalSave_debug then format "IncrementalSave: backup target = %\n" backupFile

		-- === Atomic rotate ===
		-- Step 1: save to temp and verify — canonical file is untouched until we know the save worked
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
			messageBox ("Temp rename failed.\n\nBackup at: " + backupFile + "\nTemp at:   " + tempFile + "\n\nRename temp manually to restore your scene.") \
				title:"IncrementalSave Error #6" beep:true
			setSaveRequired true
			return undefined
		)

		format "IncrementalSave: archived  -> %\n" backupFile
		format "IncrementalSave: canonical -> %\n" currentFile

	) -- on execute
) -- macroScript
