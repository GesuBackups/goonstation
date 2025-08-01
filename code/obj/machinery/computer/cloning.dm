//Cloning revival method.
//The pod handles the actual cloning while the computer manages the clone profiles

// time to show the message for before removing it
#define MESSAGE_SHOW_TIME 	5 SECONDS

ADMIN_INTERACT_PROCS(/obj/machinery/computer/cloning, proc/scan_someone, proc/try_clone)
/obj/machinery/computer/cloning
	name = "cloning console"
	desc = "Use this console to operate a cloning scanner and pod. There is a slot to insert modules - they can be removed with a screwdriver."
	icon = 'icons/obj/computer.dmi'
	icon_state = "dna"
	req_access = list(access_heads) //Only used for record deletion right now.
	object_flags = CAN_REPROGRAM_ACCESS | NO_GHOSTCRITTER
	machine_registry_idx = MACHINES_CLONINGCONSOLES
	processing_tier = PROCESSING_32TH
	power_usage = 5000
	can_reconnect = TRUE
	circuit_type = /obj/item/circuitboard/cloning
	records = list()
	var/obj/machinery/clone_scanner/scanner = null //Linked scanner. For scanning.
	var/max_pods = 3
	var/list/linked_pods = list() // /obj/machinery/clonepod
	var/currentStatusMessage = list()
	var/currentMessageNumber = 0
	var/menu = 1 //Which menu screen to display
	var/obj/item/disk/data/floppy/diskette = null //Mostly so the geneticist can steal somebody's identity while pretending to give them a handy backup profile.
	var/held_credit = 5000 // one free clone
	var/allow_dead_scanning = 0 //Can the dead be scanned in the cloner?
	var/portable = 0 //override new() proc and proximity check, for port-a-clones
	var/recordDeleting = list()
	var/allow_mind_erasure = 0 // Can you erase minds?
	var/mindwipe = 0 //Is mind wiping active?
	var/datum/bioEffect/BE = null // Any bioeffects to add upon cloning (used with the geneclone module)
	var/gen_analysis = 0 //Are we analysing the genes while reassembling the duder? (read: Do we work faster or do we give a material bonus?)
	//Sound for scans and toggling gene analysis. They need to be the same so you can fake the former with the latter
	var/sound_ping = 'sound/machines/ping.ogg'
	var/emagged = FALSE
	light_r =1
	light_g = 0.6
	light_b = 1

	disposing()
		scanner?.connected = null
		for (var/obj/machinery/clonepod/P in linked_pods)
			P.connected = null
		scanner = null
		linked_pods = list()
		diskette = null
		records = null
		STOP_TRACKING
		..()

/obj/item/cloner_upgrade
	name = "\improper NecroScan II cloner upgrade module"
	desc = "A circuit module designed to improve cloning machine scanning capabilities to the point where even skeletal remains may be scanned."
	icon = 'icons/obj/module.dmi'
	icon_state = "cloner_upgrade"
	health = 8
	w_class = W_CLASS_TINY
	throwforce = 1

/obj/item/grinder_upgrade
	name = "\improper ProBlender X enzymatic reclaimer upgrade module"
	desc = "A circuit module designed to improve enzymatic reclaimer capabilities so that the machine will be able to reclaim more matter, faster."
	icon = 'icons/obj/module.dmi'
	icon_state = "grinder_upgrade"
	health = 8
	w_class = W_CLASS_TINY
	throwforce = 1

/obj/machinery/computer/cloning/New()
	..()
	START_TRACKING
	SPAWN(0.7 SECONDS)
		connection_scan()
	return

/obj/machinery/computer/cloning/proc/records_scan()
	// check if we're busy cloning
	var/all_cloning = TRUE
	for (var/obj/machinery/clonepod/P in linked_pods)
		if (!P.attempting)
			// at least one free pod
			all_cloning = FALSE
	if (all_cloning)
		icon_state = "dnap"
		return TRUE
	// check if there's anyone we can clone
	for(var/datum/db_record/R as anything in src.records)
		var/datum/mind/mind = R["mind"]
		var/mob/selected = mind?.current
		if (!selected || (selected.mind && selected.mind.get_player()?.dnr) || !eligible_to_clone(mind))
			continue
		// else there's someone we can clone
		icon_state = "dnac"
		return TRUE
	icon_state = "dna"
	return FALSE

/obj/machinery/computer/cloning/process()
	..()
	if (!(src.status & (NOPOWER | BROKEN)))
		src.records_scan()

/obj/machinery/computer/cloning/connection_scan()
	if (src.portable)
		return
	src.scanner?.connected = null
	for (var/obj/machinery/clonepod/P in src.linked_pods)
		P.connected = null
	src.linked_pods = list()
	src.scanner = locate(/obj/machinery/clone_scanner, orange(2,src))
	for (var/obj/machinery/clonepod/P in orange(4, src))
		src.linked_pods += P
		if (!isnull(src.scanner))
			src.scanner.connected = src
			P.connected = src
		if (length(src.linked_pods) >= src.max_pods)
			break

/obj/machinery/computer/cloning/special_deconstruct(var/obj/computerframe/frame as obj)
	frame.circuit.records = src.records
	if (src.allow_dead_scanning)
		new /obj/item/cloner_upgrade (src.loc)
		src.allow_dead_scanning = 0
	if(src.allow_mind_erasure)
		new /obj/item/cloneModule/minderaser(src.loc)
		src.allow_mind_erasure = 0
	if(src.BE)
		new /obj/item/cloneModule/genepowermodule(src.loc)
		src.BE = null
	if(src.status & BROKEN)
		logTheThing(LOG_STATION, usr, "disassembles [src] (broken) [log_loc(src)]")
	else
		logTheThing(LOG_STATION, usr, "disassembles [src] [log_loc(src)]")


/obj/machinery/computer/cloning/attackby(obj/item/W, mob/user)
	if (wagesystem.clones_for_cash && istype(W, /obj/item/currency/spacecash))
		var/obj/item/currency/spacecash/cash = W
		src.held_credit += cash.amount
		cash.amount = 0
		user.show_text(SPAN_NOTICE("You add [cash] to the credit in [src]."))
		user.u_equip(W)
		qdel(W)
	else if (istype(W, /obj/item/disk/data/floppy))
		var/obj/item/disk/data/floppy/disk_to_drop = null
		if (src.diskette) //let them swap
			disk_to_drop = src.diskette
			src.diskette = null
		user.drop_item()
		W.set_loc(src)
		src.diskette = W
		user.put_in_hand_or_drop(disk_to_drop)
		boutput(user, "You insert [W].")
		playsound(src, 'sound/items/floppy_disk.ogg', 30, TRUE)
		tgui_process.update_uis(src)
		return

	else if (istype(W, /obj/item/cloner_upgrade))
		if (allow_dead_scanning || allow_mind_erasure)
			boutput(user, SPAN_ALERT("There is already an upgrade installed."))
			return

		user.visible_message("[user] installs [W] into [src].", "You install [W] into [src].")
		src.allow_dead_scanning = 1
		user.drop_item()
		logTheThing(LOG_STATION, user, "has added clone module ([W]) to ([src]) at [log_loc(user)].")
		qdel(W)

	else if (istype(W, /obj/item/cloneModule/minderaser))
		if(allow_mind_erasure || allow_dead_scanning)
			boutput(user, SPAN_ALERT("There is already an upgrade installed."))
			return
		user.visible_message("[user] installs [W] into [src].", "You install [W] into [src].")
		src.allow_mind_erasure = 1
		user.drop_item()
		logTheThing(LOG_STATION, user, "has added clone module ([W]) to ([src]) at [log_loc(user)].")
		qdel(W)
	else if (istype(W, /obj/item/cloneModule/genepowermodule))
		var/obj/item/cloneModule/genepowermodule/module = W
		if(module.BE == null)
			boutput(user, SPAN_ALERT("You need to put an injector into the module before it will work!"))
			return
		if(src.BE)
			boutput(user,SPAN_ALERT("There is already a gene module in this upgrade spot! You can remove it by blowing up the genetics computer and building a new one. Or you could just use a screwdriver, I guess."))
			return
		src.BE = module.BE
		user.drop_item()
		user.visible_message("[user] installs [module] into [src].", "You install [module] into [src].")
		logTheThing(LOG_STATION, user, "has added clone module ([W] - [module.BE]) to ([src]) at [log_loc(user)].")
		qdel(module)


	else
		..()
	return

/obj/machinery/computer/cloning/emp_act()
	if (length(src.records))
		for (var/i = 0 ; i <= (min(5,length(src.records))); i += 1) //eat up to 5 records
			var/RIP = pick(src.records)
			src.records.Remove(RIP)
			qdel(RIP)
	..()

/obj/machinery/computer/cloning/emag_act(mob/user, obj/item/card/emag/E)
	..()
	if (!src.emagged)
		src.emagged = TRUE
		playsound(src, 'sound/effects/sparks4.ogg', 50)
		logTheThing(LOG_ADMIN, user, "emagged the cloning console at \[[log_loc(src)]]")
		if(user)
			boutput(user, "You short out the access lock on [src].")
		return 1
	return 0

// message = message you want to pass to the noticebox
// status = warning/success/danger/info which changes the color of the noticebox on the frontend

/obj/machinery/computer/cloning/proc/show_message(message = "", status = "info")
	src.currentStatusMessage["text"] = message
	src.currentStatusMessage["status"] = status
	tgui_process?.update_uis(src)
	//prevents us from overwriting the wrong message
	currentMessageNumber += 1
	var/messageNumber = currentMessageNumber
	SPAWN(MESSAGE_SHOW_TIME)
	if(src.currentMessageNumber == messageNumber)
		src.currentStatusMessage["text"] = ""
		src.currentStatusMessage["status"] = ""
		tgui_process?.update_uis(src)

/obj/machinery/computer/cloning/proc/scan_mob(mob/living/carbon/human/subject as mob)
	if ((isnull(subject)) || (!ishuman(subject)))
		show_message("Error: Unable to locate valid genetic data.", "warning")
		return
	if (!src.diskette)
		show_message("Error: Please insert disk.", "warning")
		return
	if (src.diskette.read_only)
		show_message("Error: Disk is write protected.", "warning")
		return
	if((src.diskette.file_used + /datum/computer/file/clone::size + /datum/computer/file/genetics_scan::size) > src.diskette.file_amount)
		show_message("Error: Insufficient space left on disk.", "danger")
		return
	if(!allow_dead_scanning && subject.decomp_stage)
		show_message("Error: Failed to read genetic data from subject. Necrosis of tissue has been detected.")
		return
	if (!subject.bioHolder || subject.bioHolder.HasEffect("husk"))
		show_message("Error: Extreme genetic degredation present.", "danger")
		return
	if (istype(subject.mutantrace, /datum/mutantrace/kudzu))
		show_message("Error: Incompatible cellular structure.", "danger")
		return
	if (istype(subject.mutantrace, /datum/mutantrace/zombie))
		show_message("Error: Incompatible cellular structure.", "danger")
		return
	if ((subject.mob_flags & IS_BONEY) && !allow_dead_scanning)
		show_message("Error: No tissue mass present. Total ossification of subject detected.", "danger")
		return

	var/datum/mind/subjMind = subject.mind
	if ((!subjMind) || (!subjMind.key))
		if(subject.ghost?.mind)
			subjMind = subject.ghost.mind
		else if(subject.oldmind)
			if(eligible_to_clone(subject.oldmind, scanning = TRUE))
				subjMind = subject.oldmind
			else
				show_message("Error: Mental interface failure.", "warning")
				return
		else
			show_message("Error: Mental interface failure.", "warning")
			return

	var/datum/computer/file/clone/clone_file = locate() in src.diskette
	if (!isnull(clone_file))
		show_message("Existing clone record found on disk.", "info")
		return clone_file

	clone_file = new
	clone_file["ckey"] = ckey(subjMind.key)

	//use the subjects *visible* name, disguises can fool the scanner
	if (subject.face_visible())
		clone_file["name"] = subject.real_name
	else
		clone_file["name"] = subject.name
	clone_file["id"] = copytext("\ref[subjMind]", 4, 12)
	clone_file.name = "CloneRecord-[ckey(clone_file["name"])]"

	var/datum/bioHolder/H = new/datum/bioHolder(null)
	H.CopyOther(subject.bioHolder)

	clone_file["holder"] = H

	clone_file["abilities"] = null
	if (subject.abilityHolder)
		var/datum/abilityHolder/A = subject.abilityHolder.deepCopy()
		clone_file["abilities"] = A

	clone_file["traits"] = null
	if(!isnull(subject.traitHolder))
		clone_file["traits"] = subject.traitHolder.copy(null)

	clone_file["defects"] = subject.cloner_defects.copy()

	var/obj/item/implant/cloner/imp = new(subject)
	clone_file["imp"] = "\ref[imp]"

	if (!isnull(subjMind)) //Save that mind so traitors can continue traitoring after cloning.
		clone_file["mind"] = subjMind

	show_message("Subject successfully scanned.", "success")
	playsound(src.loc, sound_ping, 50, 1)
	JOB_XP(usr, "Medical Doctor", 10)

	src.diskette.root.add_file(clone_file)

	var/datum/computer/file/genetics_scan/gene_scan = create_new_dna_sample_file(subject, visible_name=TRUE)
	src.diskette.root.add_file(gene_scan)

	//label the disk, clearing other labels
	src.diskette.name_suffixes = list()
	src.diskette.name_suffix("([clone_file["name"]])")
	src.diskette.UpdateName()
	return clone_file

/obj/machinery/computer/cloning/proc/scan_someone()
	src.scan_mob(src.scanner?.occupant)

/obj/machinery/computer/cloning/proc/try_clone()
	if (!src.diskette)
		show_message("Error: Please insert disk.", "warning")
		return FALSE
	var/datum/computer/file/clone/clone_file = locate() in src.diskette.root.contents
	if (!clone_file)
		show_message("Error: No valid record found on disk.", "warning")
		return FALSE
	return src.clone_file(clone_file)

/obj/machinery/computer/cloning/proc/clone_file(datum/computer/file/clone/clone_file)
	var/obj/machinery/clonepod/pod1 = null
	for (var/obj/machinery/clonepod/P in linked_pods)
		if (isnull(pod1))
			pod1 = P
			continue

		if (P.attempting)
			// If this new pod is currently working, skip it.
			continue

		if (pod1.attempting)
			pod1 = P
			continue

		// Pick the pod that has the most progress
		if (pod1.get_progress() < P.get_progress())
			pod1 = P
			continue

		// If they're both the same progress, pick the one with the most MEAT
		if (pod1.get_progress() == P.get_progress() && pod1.meat_level < P.meat_level)
			pod1 = P
			continue

	if (!pod1)
		show_message("No cloning pod connected.", "danger")
		return
	if (pod1.attempting)
		show_message("Cloning pod in use.", "info")
		return
	if (pod1.mess)
		show_message("Abnormal reading from cloning pod.", "danger")
		return

	var/datum/mind/mind = clone_file["mind"]
	var/mob/selected = eligible_to_clone(mind)

	if (!selected)
		show_message("Can't clone: Unable to locate mind.", "danger")
		return

	if (mind.get_player()?.dnr)
		// leave the goddamn dnr ghosts alone
		show_message("Cannot clone: Subject has set DNR.", "danger")
		return

	if (inafterlifebar(selected) || isghostcritter(selected) || isVRghost(selected))
		//for deleting the mob if theyre in the bar, in vr, or a ghost critter
		var/mob/soon_to_be_deleted = selected
		boutput(selected, SPAN_NOTICE("You are being returned to the land of the living!"))
		selected = soon_to_be_deleted.ghostize()
		qdel(soon_to_be_deleted)

	// at this point selected = the dude we wanna revive.

	if (wagesystem.clones_for_cash)
		var/datum/db_record/Ba = FindBankAccountByName(clone_file["name"])
		var/account_credit = 0

		if (Ba?["current_money"])
			account_credit = Ba["current_money"]

		if ((src.held_credit + account_credit) >= wagesystem.clone_cost)
			if (pod1.growclone(selected, clone_file["name"], clone_file["mind"], clone_file["holder"], clone_file["abilities"] , clone_file["traits"], clone_file["defects"]))
				var/from_account = min(wagesystem.clone_cost, account_credit)
				if (from_account > 0)
					Ba["current_money"] -= from_account
				src.held_credit -= (wagesystem.clone_cost - from_account)
				show_message("Payment of [wagesystem.clone_cost] credits accepted. [from_account > 0 ? "Deducted [from_account] credits from [clone_file["name"]]'s account.' " : ""][from_account < wagesystem.clone_cost ? "Deducted [wagesystem.clone_cost - from_account] credits from machine credit." : ""] Cloning cycle activated.", "info")
				src.menu = 1
				. = TRUE
			else
				show_message("Unknown error when trying to start cloning process.", "info")
		else
			show_message("Insufficient funds to begin clone cycle.", "warning")

	else if (pod1.growclone(selected, clone_file["name"], clone_file["mind"], clone_file["holder"], clone_file["abilities"] , clone_file["traits"], clone_file["defects"]))
		show_message("Cloning cycle activated.", "success")
		. = TRUE
		JOB_XP(usr, "Medical Doctor", 15)
		src.menu = 1

	if (.) //only wipe the disk if we're 100% sure we've succeeded
		var/read_only = src.diskette.read_only
		src.diskette.read_only = FALSE
		src.diskette.root.remove_file(clone_file)
		var/datum/computer/file/genetics_scan/gene_file = locate() in src.diskette.root.contents
		if (gene_file)
			src.diskette.root.remove_file(gene_file)
		src.diskette.read_only = read_only

		//clear labels, we're empty now
		src.diskette.name_suffixes = list()
		src.diskette.UpdateName()

/// Check if a mind has a current mob, a client, and is dead/a ghost/doing afterlife stuff.
/// Scanning var controls whether we will return ghosts, because ghosts needs special handling in clone scans
/// to ensure they're not using a body that they've been cloned from before
proc/eligible_to_clone(datum/mind/mind, scanning = FALSE)
	if (!mind)
		return null

	if (!mind.current)
		return null

	var/mob/M = mind.current

	if (!M.client)
		return null

	if (istype(M, /mob/new_player))
		return null

	if(istype(M, /mob/dead/target_observer))
		var/mob/dead/target_observer/tobserver = M
		if(!tobserver.is_respawnable)
			return null
	if(iswraith(M))
		return null
	if((!scanning && (isdead(M) || isobserver(M))) || isVRghost(M) || inafterlifebar(M) || isghostcritter(M))
		return M
	return null

/// find a ghost mob (or a ghost respawned as critter in vr/afterlife bar)
proc/find_ghost_by_key(var/find_key)
	if (!find_key)
		return null

	var/datum/player/player = find_player(find_key)
	if (player?.client?.mob)
		var/mob/M = player.client.mob
		if(istype(M, /mob/dead/target_observer))
			var/mob/dead/target_observer/tobserver = M
			if(!tobserver.is_respawnable)
				return null
		if(iswraith(M))
			return null
		if (isdead(M) || isVRghost(M) || inafterlifebar(M) || isghostcritter(M))
			return M
	return null

#define PROCESS_IDLE 0
#define PROCESS_STRIP 1
#define PROCESS_MINCE 2

TYPEINFO(/obj/machinery/clone_scanner)
	mats = 15

/obj/machinery/clone_scanner
	name = "cloning machine scanner"
	desc = "A machine that you stuff living, and freshly not-so-living people into in order to scan them for cloning"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_0"
	density = 1
	var/locked = 0
	var/mob/occupant = null
	anchored = ANCHORED
	soundproofing = 10
	event_handler_flags = USE_FLUID_ENTER
	var/obj/machinery/computer/cloning/connected = null

	// In case someone wants a perfectly safe device. For some weird reason.
	var/can_meat_grind = 1
	//Double functionality as a meat grinder
	var/list/obj/machinery/clonepod/pods
	// How long to run
	var/process_timer = 0
	var/timer_length = 0
	// Automatically strip the target of their equipment
	var/auto_strip = 1
	// Check if the target is a living human before mincing
	var/mince_safety = 1
	// How far away to find clone pods
	var/pod_range = 4
	// What we are working on at the moment
	var/active_process = PROCESS_IDLE
	// If we should start the mincer after the stripper (lol)
	var/automatic_sequence = 0
	// Our ID for mapping
	var/id = ""
	// If upgraded or not
	var/upgraded = 0

	allow_drop()
		return 0

	New()
		..()
		src.create_reagents(100)

	relaymove(mob/user as mob, dir)
		eject_occupant(user)

	disposing()
		connected?.scanner = null
		connected = null
		pods = null
		if(occupant)
			occupant.set_loc(get_turf(src.loc))
			occupant = null
		..()

	Click(location, control, params)
		if(!src.ghost_observe_occupant(usr, src.occupant))
			. = ..()

	MouseDrop_T(mob/living/target, mob/user)
		if (!istype(target) || isAI(user))
			return

		if (BOUNDS_DIST(src, user) > 0 || BOUNDS_DIST(user, target) > 0)
			return

		if (target == user)
			move_mob_inside(target, user)
		else if (can_operate(user))
			var/previous_user_intent = user.a_intent
			user.set_a_intent(INTENT_GRAB)
			user.drop_item()
			target.Attackhand(user)
			user.set_a_intent(previous_user_intent)
			SPAWN(user.combat_click_delay + 2)
				if (can_operate(user))
					if (istype(user.equipped(), /obj/item/grab))
						src.Attackby(user.equipped(), user)
		return


	proc/can_operate(var/mob/M)
		if (!(BOUNDS_DIST(src, M) == 0))
			return FALSE
		if (is_incapacitated(M))
			return FALSE
		if (src.occupant)
			boutput(M, SPAN_NOTICE("<B>The scanner is already occupied!</B>"))
			return FALSE

		.= TRUE

	verb/move_inside()
		set src in oview(1)
		set category = "Local"

		move_mob_inside(usr, usr)
		return

	proc/move_mob_inside(var/mob/M, var/mob/user)
		if (!can_operate(user) || !ishuman(M) || QDELETED(M))
			return

		M.remove_pulling()
		M.set_loc(src)
		src.occupant = M
		src.icon_state = "scanner_1"

		for(var/obj/O in src)
			O.set_loc(src.loc)

		src.add_fingerprint(user)
		src.connected?.updateUsrDialog()

		playsound(src.loc, 'sound/machines/sleeper_close.ogg', 50, 1)

	attack_hand(mob/user)
		..()
		eject_occupant(user)

	mouse_drop(mob/user as mob)
		if (istype(user) && can_operate(user))
			eject_occupant(user)
		else
			..()

	verb/eject()
		set src in oview(1)
		set category = "Local"

		eject_occupant(usr)
		return

	verb/eject_occupant(var/mob/user)
		if (!src.can_eject_occupant(user))
			return
		src.go_out()
		add_fingerprint(user)

	attackby(var/obj/item/grab/G, user)
		if ((!( istype(G, /obj/item/grab) ) || !( ismob(G.affecting) )))
			return

		if (src.occupant)
			boutput(user, SPAN_NOTICE("<B>The scanner is already occupied!</B>"))
			return

		move_mob_inside(G.affecting, user)
		qdel(G)
		return

	proc/go_out()
		if ((!( src.occupant ) || src.locked))
			return
		if(!src.occupant.disposed)
			src.occupant.set_loc(get_turf(src))
		return

	Exited(Obj, newloc)
		. = ..()
		if(Obj == src.occupant)
			src.occupant = null

			for(var/atom/movable/A in src)
				if(!QDELETED(A))
					A.set_loc(src.loc)

			src.icon_state = "scanner_0"

			playsound(src.loc, 'sound/machines/sleeper_open.ogg', 50, 1)

	was_deconstructed_to_frame(mob/user)
		src.go_out()

	proc/set_lock(var/lock_status)
		if(lock_status && !locked)
			locked = 1
			playsound(src, 'sound/machines/click.ogg', 50, TRUE)
			boutput(occupant, SPAN_ALERT("\The [src] locks shut!"))
		else if(!lock_status && locked)
			locked = 0
			playsound(src, 'sound/machines/click.ogg', 50, TRUE)
			boutput(occupant, SPAN_NOTICE("\The [src] unlocks!"))

	// Meat grinder functionality.
	proc/find_pods()
		if (!islist(src.pods))
			src.pods = list()
		if (!isnull(src.id) && genResearch && islist(genResearch.clonepods) && length(genResearch.clonepods))
			for (var/obj/machinery/clonepod/pod as anything in genResearch.clonepods)
				if (pod.id == src.id && !src.pods.Find(pod))
					src.pods += pod
					DEBUG_MESSAGE("[src] adds pod [log_loc(pod)] (ID [src.id]) in genResearch.clonepods")
		else
			for (var/obj/machinery/clonepod/pod in orange(src.pod_range))
				if (!src.pods.Find(pod))
					src.pods += pod
					DEBUG_MESSAGE("[src] adds pod [log_loc(pod)] in orange([src.pod_range])")

	process()
		switch(active_process)
			if(PROCESS_IDLE)
				UnsubscribeProcess()
				process_timer = 0
				return
			if(PROCESS_MINCE)
				do_mince()
			if(PROCESS_STRIP)
				do_strip()

	proc/report_progress()
		switch(active_process)
			if(PROCESS_IDLE)
				. = "Idle."
			if(PROCESS_MINCE)
				. = "Reclamation process [round(process_timer/timer_length)*100] % complete..."
			if(PROCESS_STRIP)
				. = "In progress..."

	proc/start_mince()
		active_process = PROCESS_MINCE
		timer_length = 15 + rand(-5, 5)
		process_timer = timer_length
		set_lock(1)
		boutput(occupant, "<span style='color:red;font-weight:bold'>A whirling blade slowly begins descending upon you!</span>")
		playsound(src, 'sound/machines/mixer.ogg', 50, TRUE)
		SubscribeToProcess()

	proc/start_strip()
		active_process = PROCESS_STRIP
		set_lock(1)
		boutput(occupant, SPAN_ALERT("Hatches open and tiny, grabby claws emerge!"))

		SubscribeToProcess()

	proc/do_mince()
		if (process_timer-- < 1)
			active_process = PROCESS_IDLE
			src.occupant.death(TRUE)
			src.occupant.ghostize()
			qdel(src.occupant)
			DEBUG_MESSAGE("[src].reagents.total_volume on completion of cycle: [src.reagents.total_volume]")

			if (islist(src.pods) && pods.len && src.reagents.total_volume)
				for (var/obj/machinery/clonepod/pod in src.pods)
					src.reagents.trans_to(pod, (src.reagents.total_volume / max(pods.len, 1))) // give an equal amount of reagents to each pod that happens to be around
					DEBUG_MESSAGE("[src].reagents.trans_to([pod] [log_loc(pod)], [src.reagents.total_volume]/[max(pods.len, 1)])")
			process_timer = 0
			active_process = PROCESS_IDLE
			set_lock(0)
			automatic_sequence = 0
			return

		var/mult = src.upgraded ? 2 : 1
		src.reagents.add_reagent("blood", 2 * mult)
		src.reagents.add_reagent("meat_slurry", 2 * mult)
		if (prob(2))
			src.reagents.add_reagent("beff", 1 * mult)

		// Mess with the occupant
		var/damage = round(200 / timer_length) + rand(1, 10)
		src.occupant.TakeDamage(zone="All", brute=damage)
		bleed(occupant, damage * 2, 0)
		if(prob(50))
			playsound(src, 'sound/machines/mixer.ogg', 50, TRUE)
		if(prob(30))
			SPAWN(0.3 SECONDS)
				playsound(src.loc, pick('sound/impact_sounds/Flesh_Stab_1.ogg', \
									'sound/impact_sounds/Slimy_Hit_3.ogg', \
									'sound/impact_sounds/Slimy_Hit_4.ogg', \
									'sound/impact_sounds/Flesh_Break_1.ogg', \
									'sound/impact_sounds/Flesh_Tear_1.ogg', \
									'sound/impact_sounds/Generic_Snap_1.ogg', \
									'sound/impact_sounds/Generic_Hit_1.ogg'), 100, 5)

	proc/do_strip()
		//Remove one item each cycle
		var/obj/item/to_remove
		if(src.occupant)
			to_remove = occupant.unequip_random()

		if(to_remove)
			if(prob(70))
				boutput(occupant, SPAN_ALERT("\The arms [pick("snatch", "grab", "steal", "remove", "nick", "blag")] your [to_remove.name]!"))
				playsound(src, "sound/misc/rustle[rand(1,5)].ogg", 50, 1)
			to_remove.set_loc(src.loc)
		else
			if(automatic_sequence)
				start_mince()
			else
				set_lock(0)
				active_process = PROCESS_IDLE

/obj/machinery/computer/cloning/ui_act(action, params, datum/tgui/ui)
	. = ..()
	if (.)
		return

	var/any_active = FALSE
	for (var/obj/machinery/clonepod/P in linked_pods)
		if (P.attempting)
			any_active = TRUE

	switch(action)
		if("scan")
			if(usr == src.scanner.occupant)
				boutput(usr, SPAN_ALERT("You can't quite reach the scan button from inside the scanner, darn!"))
				return TRUE
			if(QDELETED(src.scanner))
				show_message("No scanner connected.", "warning")
				return FALSE
			src.scan_mob(src.scanner.occupant)
			. = TRUE
		if("toggleGeneticAnalysis")
			if (any_active)
				show_message("Cannot toggle any modules while cloner is active.", "warning")
				. = TRUE
			else
				src.gen_analysis = !src.gen_analysis
				if (!ON_COOLDOWN(src, "sound_genetoggle", 2 SECONDS))
					playsound(src.loc, sound_ping, 50, 1)
				. = TRUE

		if("diskAction")
			if (BOUNDS_DIST(ui.user, src) || isintangible(ui.user))
				return
			var/obj/item/disk/data/floppy/disk = ui.user.equipped()
			if (src.diskette && !istype(disk))
				usr.put_in_hand_or_drop(src.diskette)
				src.diskette = null
				playsound(src, 'sound/items/floppy_disk.ogg', 30, TRUE)
				. = TRUE
				return
			if (istype(disk))
				src.attackby(disk, ui.user) //insert or swap
			else if (istype(disk, /obj/item/disk))
				boutput(ui.user, SPAN_ALERT("[disk] doesn't quite fit in [src]'s slot!"))
		if ("clone")
			if (src.try_clone())
				. = TRUE
		if("toggleLock")
			if (!isnull(src.scanner))
				if ((!src.scanner.locked) && (src.scanner.occupant))
					src.scanner.locked = 1
					. = TRUE
				else
					src.scanner.locked = 0
					. = TRUE
		if("mindWipeToggle")
			if (any_active || !src.allow_mind_erasure)
				show_message("Cannot toggle any modules while cloner is active.", "warning")
				. = TRUE
			else
				src.mindwipe = !src.mindwipe
				. = TRUE

/obj/machinery/computer/cloning/ui_data(mob/user)

	. = list(
		"allowedToDelete" = (src.allowed(user) || src.emagged),
		"scannerGone" = isnull(src.scanner),
		"occupantScanned" = FALSE,

		"message" = src.currentStatusMessage,
		"disk" = !isnull(src.diskette),

		"allowDeadScan" = src.allow_dead_scanning,
		"allowMindErasure" = src.allow_mind_erasure,
		"clonesForCash" = wagesystem.clones_for_cash,
		"balance" = src.held_credit,

		"mindWipe" = src.mindwipe,
		"geneticAnalysis" = src.gen_analysis,
		"podNames" = list(),
		"meatLevels" = list(),
		"podSpeed" = list(),
		"podEfficient" = list(),
		"cloneHack" = list(),
		"completion" = list(),
	)
	for (var/obj/machinery/clonepod/P in src.linked_pods)
		.["podNames"] += P.name
		.["meatLevels"] += P.meat_level
		.["podSpeed"] += P.is_speedy
		.["podEfficient"] += P.is_efficient
		.["cloneHack"] += P.clonehack
		.["completion"] += P.get_progress()
	if(!isnull(src.scanner))
		. += list(
			"scannerOccupied" = src.scanner.occupant,
			"scannerLocked" = src.scanner.locked,
		)

	. += list(
		"diskReadOnly" = src.diskette?.read_only,
		"diskHasRecord" = !!(locate(/datum/computer/file/clone) in src.diskette?.root.contents),
		"diskColor" = src.diskette?.disk_color,
		"diskName" = src.diskette?.disk_name()
	)

/obj/machinery/computer/cloning/ui_interact(mob/user, datum/tgui/ui)
	ui = tgui_process.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CloningConsole", src.name)
		ui.open()

#undef PROCESS_IDLE
#undef PROCESS_STRIP
#undef PROCESS_MINCE
