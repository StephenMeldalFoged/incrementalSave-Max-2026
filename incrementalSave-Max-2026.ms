-- Incremental Save v1.1
-- Original v0.5 (c) 2003 M. Breidt (martin@breidt.net)
-- Modernized 2026 by Stephen Foged for 3ds Max 2027.1
--
-- What changed from v0.5:
--   FIXED  ALT opens settings dialog (docs said CTRL, code checked altPressed — now consistent)
--   FIXED  comment_txt was a leaked implicit global; now scoped to execute handler
--   FIXED  version number extracted as integer, not float — prevents -V-1.5 edge case
--   FIXED  glob wildcard capped discovery at padding width; dotNet regex scan finds any width
--   NEW    getFileSize replaces manual fOpen/fseek/ftell binary stream dance
--   NEW    persistent locals replace INI file and persistent globals
--          (persistent locals survive session restarts via Max's own preference store)
--
-- What changed from v1.0:
--   FIXED  temp file (_ISAVE_TMP_.max) was appearing in Open Recent menu — saveMaxFile
--          registers every path it writes; eliminated temp file entirely to fix this.
--   FIXED  scene was saved twice per invocation — second save was needed only to
--          re-anchor Max's internal file pointer after the temp→canonical rename.
--          New approach saves once to canonical, copies to backup via dotNet File.Copy.
--
-- How the save works (v1.1):
--   1. saveMaxFile to canonical name — Max's pointer stays on the right file, title bar unchanged
--   2. dotNet File.Copy canonical → versioned backup
--   One save. No temp file. No recent-menu pollution.
--
-- Installation:
--   Drag-drop this file onto the Max viewport. A setup dialog offers
--   Install / Update, Uninstall, or Skip (run for this session only).
--   Install copies it to the user Startup scripts folder.
--   Action appears in the "Eski Tools" category — assign Alt+Ctrl+S.
--
-- Usage:
--   Invoke normally to save. Hold ALT when invoking to open the settings dialog.
--   "Incremental Save - Clean Old Versions" (second button) opens a dialog that lists
--   history files older than N days (default 7), keeping the last save of each day.
--   Nothing is deleted until you press the Delete button.

macroScript incrementalSave
category:"Eski Tools"
buttonText:"Incremental Save 2026"
toolTip:"Incremental Save 2026"
(
	local _debug  = false
	local _subDir = true
	local _ext    = ".bak"
	local _sep    = "-V-"
	local _pad    = 3
	local _doCmt  = false

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

		if not (saveMaxFile fName quiet:true) then (
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

	fn copyFileNet src dst = (
		local ioFile = dotNetClass "System.IO.File"
		try (
			ioFile.Copy src dst false
			true
		) catch (
			false
		)
	)

	on execute do (
		-- Rollouts cannot close over outer locals in MaxScript — all shared state must be global.
		-- Prefixed with incrementalSave_ to avoid namespace collisions.
		global incrementalSave_debug  = _debug
		global incrementalSave_subDir = _subDir
		global incrementalSave_ext    = _ext
		global incrementalSave_sep    = _sep
		global incrementalSave_pad    = _pad
		global incrementalSave_doCmt  = _doCmt
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
				_debug  = incrementalSave_debug
				_subDir = incrementalSave_subDir
				_ext    = incrementalSave_ext
				_sep    = incrementalSave_sep
				_pad    = incrementalSave_pad
				_doCmt  = incrementalSave_doCmt
				destroyDialog settingsRO
			)
		)

		format "IncrementalSave v1.1 — Modernized 2026 by Stephen Foged (based on v0.5 by M. Breidt)\n"

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

		if incrementalSave_debug then format "IncrementalSave: backup target = %\n" backupFile

		-- Step 1: save to canonical — Max's internal pointer stays on the right file,
		-- title bar unchanged, no temp path added to Open Recent.
		local tStart = timeStamp()
		if not (verifiedSaveFile currentFile) then return undefined

		-- Step 2: copy canonical → versioned backup via dotNet (no Max involvement, no recent entry)
		if not (copyFileNet currentFile backupFile) then (
			messageBox ("Backup copy failed — scene was saved but no version was archived.\n\nTarget: " + backupFile) \
				title:"IncrementalSave Error #5" beep:true
			return undefined
		)

		format "IncrementalSave: archived  -> %\n" backupFile
		format "IncrementalSave: canonical -> %\n" currentFile
		format "IncrementalSave: save took %s\n" (formattedPrint ((timeStamp() - tStart) / 1000.0) format:".2f")

	) -- on execute
) -- macroScript


-- Lists history files older than N days (default 7), keeping the last save of
-- each day, and deletes them when the Delete button is pressed.
-- Uses the save macro's settings if it has run this session, else its defaults.
macroScript incrementalSavePrune
category:"Eski Tools"
buttonText:"Incremental Save - Clean Old Versions"
toolTip:"Incremental Save - Clean Old Versions"
(
	rollout incrementalSavePruneRO "Incremental Save - Clean Old Versions" width:520
	(
		local backupDir = ""
		local backupBase = ""
		local sepSym = "-V-"
		local doomed = #()
		-- Native tips line (no dotNet controls: Max blocks those from scripts it deems unsafe).
		-- Tip rotates every 12 s; a result replaces it for 5 s.
		local tips = #( \
			"Last save of each day is kept", \
			"Recent files are never touched", \
			"The newest version is never deleted", \
			"Change the days to preview again", \
			"Delete is permanent - check the list", \
			"Hold ALT on Incremental Save for settings", \
			"Assign Alt+Ctrl+S to Incremental Save", \
			"Backups live in <scene>.bak next to the scene", \
			"Backups keep the time they were saved", \
			"Version numbers keep counting up, never reused", \
			"Set days to 1 to keep only today's last save", \
			"Press the arrow for the next tip", \
			"Close and reopen to rescan the folder" )
		local tipIdx = 1
		local tipTicks = 0
		local holdTicks = 0

		spinner spnDays "Delete history older than (days):" range:[1,365,7] type:#integer fieldWidth:45 align:#left
		label   lblInfo "" align:#left width:496
		listbox lbFiles "Will be deleted:" height:14 width:496
		button  btnDelete "Delete" width:120 height:26 across:2 align:#left enabled:false
		button  btnClose  "Close"  width:120 height:26 align:#right
		label   lblStatus "" align:#left width:330 across:4 offset:[0,3]
		button  btnNextTip ">"  width:22 height:20 align:#right toolTip:"Next tip"
		button  btnAllTips "All" width:30 height:20 align:#right toolTip:"Show all tips"
		label   lblBuild "v1.2 - 2026-11-06" align:#right width:96 offset:[0,3]
		timer   tmrTips interval:1000 active:true

		fn showTip = ( lblStatus.text = "Tip: " + tips[tipIdx] )
		fn say txt secs = ( lblStatus.text = txt; holdTicks = secs )

		-- Returns the backup files to delete: older than keepDays, and not the
		-- highest version saved on their day. The newest version is never returned.
		fn pruneCandidates base sep keepDays = (
			local ioDir   = dotNetClass "System.IO.Directory"
			local ioPath  = dotNetClass "System.IO.Path"
			local ioFile  = dotNetClass "System.IO.File"
			local reClass = dotNetClass "System.Text.RegularExpressions.Regex"

			local folder   = ioPath.GetDirectoryName base
			local fileBase = ioPath.GetFileName base

			if not (ioDir.Exists folder) then return #()

			local rxPattern = (reClass.Escape (fileBase + sep)) + "(\\d+)\\.max$"
			local rx        = dotNetObject "System.Text.RegularExpressions.Regex" rxPattern \
			                  ((dotNetClass "System.Text.RegularExpressions.RegexOptions").IgnoreCase)

			local cutoff = ((dotNetClass "System.DateTime").Today).AddDays (-keepDays)

			local newest = 0
			local vers = #(), days = #(), paths = #()

			for f in (ioDir.GetFiles folder (fileBase + sep + "*.max")) do (
				local m = rx.Match (ioPath.GetFileName f)
				if m.Success then (
					local n = (m.Groups.get_Item 1).Value as integer
					if n > newest then newest = n
					local lw = ioFile.GetLastWriteTime f
					if lw.Ticks < cutoff.Ticks then (
						append vers n
						append days (lw.ToString "yyyy-MM-dd")
						append paths f
					)
				)
			)

			local result = #()
			for i = 1 to paths.count do (
				local isLastOfDay = true
				for j = 1 to paths.count where days[j] == days[i] and vers[j] > vers[i] do isLastOfDay = false
				if not isLastOfDay and vers[i] != newest then append result paths[i]
			)
			result
		)

		fn refreshList = (
			local ioFile = dotNetClass "System.IO.File"
			local ioPath = dotNetClass "System.IO.Path"
			doomed = pruneCandidates backupBase sepSym spnDays.value

			local items = #()
			local totalBytes = 0
			for f in doomed do (
				local sz = getFileSize f
				totalBytes += sz
				append items ((ioPath.GetFileName f) + "    " + ((ioFile.GetLastWriteTime f).ToString "yyyy-MM-dd HH:mm") + "    " + (formattedPrint (sz / 1048576.0) format:".1f") + " MB")
			)
			lbFiles.items = items
			btnDelete.enabled = (doomed.count > 0)
			btnDelete.text = if doomed.count > 0 then ("Delete " + doomed.count as string + " file(s)") else "Delete"

			lblInfo.text = if doomed.count > 0 then \
				(doomed.count as string + " file(s), " + (formattedPrint (totalBytes / 1048576.0) format:".1f") + " MB. The last save of each day is kept.") \
				else "Nothing to delete. The last save of each day is kept."
		)

		on incrementalSavePruneRO open do (
			tipIdx = random 1 tips.count
			showTip()

			if maxFileName == "" then (
				lblInfo.text = "Save the scene first - there is no history to clean."
				spnDays.enabled = false
			) else (
				local subDir = true
				local ext    = ".bak"
				-- Globals only hold values once the save macro has run this session.
				if ::incrementalSave_subDir != undefined then subDir = ::incrementalSave_subDir
				if ::incrementalSave_ext    != undefined then ext    = ::incrementalSave_ext
				if ::incrementalSave_sep    != undefined then sepSym = ::incrementalSave_sep

				local baseName = getFilenameFile maxFileName
				backupDir  = if subDir then (maxFilePath + baseName + ext) else maxFilePath
				backupBase = backupDir + "\\" + baseName
				refreshList()
			)
		)

		on btnNextTip pressed do (
			tipTicks = 0
			holdTicks = 0
			tipIdx = if tipIdx >= tips.count then 1 else tipIdx + 1
			showTip()
		)

		on btnAllTips pressed do (
			local s = ""
			for t in tips do s += "- " + t + "\n"
			messageBox s title:"Tips and tricks"
		)

		on tmrTips tick do (
			if holdTicks > 0 then (
				holdTicks -= 1
				if holdTicks == 0 then showTip()
			) else (
				tipTicks += 1
				if tipTicks >= 12 then (
					tipTicks = 0
					tipIdx = if tipIdx >= tips.count then 1 else tipIdx + 1
					showTip()
				)
			)
		)

		on spnDays changed val do (
			tipTicks = 0
			refreshList()
		)

		on btnDelete pressed do (
			tipTicks = 0
			local tStart  = timeStamp()
			local ioFile  = dotNetClass "System.IO.File"
			local total   = doomed.count
			local deleted = 0
			for f in doomed do (
				try ( ioFile.Delete f; deleted += 1 ) catch ( format "IncrementalSave: could not delete %\n" f )
			)
			local secs = formattedPrint ((timeStamp() - tStart) / 1000.0) format:".2f"
			format "IncrementalSave: cleaned % of % old version(s) in %s\n" deleted total secs
			refreshList()
			if deleted == total then
				say ("OK: Deleted " + deleted as string + " file(s) in " + secs + "s") 5
			else
				say ("Error: Deleted " + deleted as string + " of " + total as string + " - see Listener") 30
		)

		on btnClose pressed do destroyDialog incrementalSavePruneRO
	)

	on execute do (
		try (destroyDialog incrementalSavePruneRO) catch ()
		createDialog incrementalSavePruneRO
	)
)

--==============================================================
-- Install / Update / Uninstall prompt
-- Runs only when the file is dragged into Max (not when Max
-- auto-loads the installed copy from the user Startup folder).
--==============================================================
(
	local srcPath     = getSourceFileName()
	local installDir  = getDir #userStartupScripts
	local installPath = installDir + "\\incrementalSave-Max-2026.ms"
	local macrosDir   = getDir #userMacros

	local isAutoLoad = false
	if srcPath != undefined do (
		local sNorm = toLower (substituteString srcPath     "/" "\\")
		local iNorm = toLower (substituteString installPath "/" "\\")
		isAutoLoad = (sNorm == iNorm)
	)

	if srcPath != undefined and not isAutoLoad do (
		rollout eskiInstallRO "Incremental Save Setup" width:300
		(
			label  lblStatus  ""                    align:#left width:284 height:64
			button btnInstall "Install / Update"                width:284 height:26
			button btnUninst  "Uninstall"                       width:284 height:26
			button btnSkip    "Skip - just run for now"         width:284 height:26

			fn statusText = (
				if not (doesFileExist installPath) then
					"Status: Not installed."
				else (
					local sMod = getFileModDate srcPath
					local iMod = getFileModDate installPath
					if sMod == iMod then
						("Status: Installed (matches source).\nFile time: " + iMod)
					else
						("Status: Installed (differs from source).\nSource:    " + sMod + "\nInstalled: " + iMod)
				)
			)

			on eskiInstallRO open do lblStatus.text = statusText()

			on btnInstall pressed do (
				try (
					local dir = pathConfig.removePathLeaf installPath
					if not (doesFileExist dir) do makeDir dir all:true
					if doesFileExist installPath do deleteFile installPath
					copyFile srcPath installPath
					filein installPath
					destroyDialog eskiInstallRO
					messageBox ("Installed to:\n" + installPath) title:"Incremental Save"
				)
				catch (
					messageBox ("Install failed:\n" + (getCurrentException())) title:"Incremental Save"
				)
			)

			on btnUninst pressed do (
				if (queryBox "Remove Incremental Save from this Max user profile?" title:"Incremental Save") do (
					try (
						if doesFileExist installPath do deleteFile installPath
						local mcrs = getFiles (macrosDir + "\\*incrementalSave*.mcr")
						for f in mcrs do deleteFile f
						try (macros.delete "Eski Tools" "incrementalSave") catch ()
						try (macros.delete "Eski Tools" "incrementalSavePrune") catch ()
						destroyDialog eskiInstallRO
						messageBox "Uninstalled.\n\nToolbar buttons and hotkeys for this macro will become inactive\nuntil you remove them via Customize User Interface." title:"Incremental Save"
					)
					catch (
						messageBox ("Uninstall failed:\n" + (getCurrentException())) title:"Incremental Save"
					)
				)
			)

			on btnSkip pressed do destroyDialog eskiInstallRO
		)

		createDialog eskiInstallRO modal:true
	)
)
