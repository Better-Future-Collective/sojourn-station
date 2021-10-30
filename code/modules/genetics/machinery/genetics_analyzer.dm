#define MENU_MAIN 1
#define MENU_MERGE 2
#define MENU_COMBINE 3
#define MENU_PROCESSING 4
#define MENU_ANALYZE 5
#define MENU_COMBINE_RESULT 6
#define MENU_IRRADIATE_RESULT 7
/*
=========================================================================================================================================
Belvoix Genetic Analyzer

This is the workhorse of the department. Every other machine in the department is built to eventually allow genetic sample plates to be
loaded into this device for analysis. Without this machine, players are left in the dark about which mutations are being produced, and
cannot isolate or combine desired genes.
=========================================================================================================================================

*/
/obj/machinery/genetics/gene_analyzer
	name = "Belvoix Genetic Analyzer"
	desc = "An extremely complex device made to analyze the patterns in DNA and apply them to other creatures."
	density = TRUE
	anchored = TRUE
	//TODO:
	icon = 'icons/obj/salvageable.dmi'
	icon_state = "implant_container0"

	//List of genetics sample plates loaded into the device
	var/list/sample_plates = list()

	//Maximum amount of plates allowed in the analyzer, subject to upgrading based on parts
	var/max_plates = 5

	//Maximum amount of mutations identified every time a sample plate is consumed for analysis.
	//Subject to upgrading based on parts.
	var/max_analyzed_per_destruction = 2

	//The presently selected holder
	var/obj/item/genetics/sample/active_sample = null

	//The presently selected mutagen (within the genetics holder)
	var/datum/genetics/mutation/active_mutation = null

	//A list of virtual mutation keys that the Analyzer recognizes as real
	var/list/known_mutations = null

	var/datum/genetics/genetics_holder/mutations_to_combine = new /datum/genetics/genetics_holder()
	var/mutations_combining_count = 0
	var/menu_state = MENU_MAIN //1 is basic menu, 2 is merge Menu


	var/debug_ui_data = null


/obj/machinery/genetics/gene_analyzer/attackby(obj/item/I, mob/user)
	if(default_deconstruction(I, user))
		return
	if(default_part_replacement(I, user))
		return

	//Inserting a sample
	if(istype(I, /obj/item/genetics/sample))
		var/obj/item/genetics/sample/incoming_sample = I

		if(sample_plates.len >= max_plates)
			to_chat(user, SPAN_WARNING("The Analyzer is full."))
			return

		if(user.unEquip(I, src))
			sample_plates += incoming_sample
			to_chat(user, SPAN_WARNING("You load a Sample plate into the Analyzer."))
			update_icon()
			return
	else
		. = ..()

/obj/machinery/genetics/gene_analyzer/attack_hand(mob/user)
	if(..())
		return TRUE
	ui_interact(user)

/obj/machinery/genetics/gene_analyzer/proc/eject(var/obj/item/genetics/sample/outbound_sample)
	log_debug("Called sample plate eject function")
	if(outbound_sample)
		outbound_sample.forceMove(loc)
		outbound_sample.genetics_holder.unmark_all_mutations()
		sample_plates -= outbound_sample

		if(active_sample && active_sample.unique_id == outbound_sample.unique_id)
			active_sample = null

/obj/machinery/genetics/gene_analyzer/update_icon()
	if(sample_plates.len >= max_plates)
		icon_state = "implant_container1"
	else
		icon_state = "implant_container0"

/obj/machinery/genetics/gene_analyzer/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = NANOUI_FOCUS)
	// this is the data which will be sent to the ui
	var/list/data = form_data()
	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "genetic_analyzer.tmpl", "GeneAnalyzer", 1000, 800)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(TRUE)
		ui.set_auto_update_layout(TRUE)

//Filling this with unique id's instead of objects for the most part, so it doesn't slow down nanoUI
//Gotta make this interface slick it sees a lot of use.
/obj/machinery/genetics/gene_analyzer/proc/form_data()
	var/list/data = list()

	data["menu_state"] = menu_state

	var/sample_plate_data
	for(var/obj/item/genetics/sample/selected_sample in sample_plates)
		if(menu_state == MENU_MERGE && active_sample && active_sample.unique_id == selected_sample.unique_id)
			continue
		else
			sample_plate_data += list(selected_sample.sample_data())
	data["sample_plates"] = sample_plate_data

	var/active_sample_data
	if(active_sample)
		active_sample_data = active_sample.sample_data()
	data["active_sample"] = active_sample_data

	var/active_mutation_data
	if(active_mutation)
		active_mutation_data = active_mutation.ui_data()
	data["active_mutation"] = active_mutation_data

	var/mutations_to_combine_data
	if(mutations_to_combine)
		mutations_to_combine_data = mutations_to_combine.ui_data()
	data["mutations_to_combine"] = mutations_to_combine_data

	var/can_combine = FALSE
	if(mutations_combining_count >= 2)
		can_combine = TRUE
	data["can_combine"] = can_combine

	debug_ui_data = data

	return data

/obj/machinery/genetics/gene_analyzer/Topic(href, href_list)
	if(..())
		return FALSE

	if(href_list["back"])
		//Add back the mutations we removed.
		if(menu_state == MENU_COMBINE)
			for(var/datum/genetics/mutation/target_mutation in mutations_to_combine.mutation_pool)
				var/datum/genetics/mutation/new_mutation = target_mutation.copy()
				active_sample.genetics_holder.addMutation(new_mutation)
			mutations_to_combine.removeAllMutations()
		active_mutation = null
		active_sample = null
		menu_state = MENU_MAIN
		mutations_combining_count = 0
		mutations_to_combine.removeAllMutations()
		return TRUE

	if(menu_state == MENU_MAIN)
		if(href_list["eject"])
			var/eject_id = text2num(href_list["eject"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				var/unique_test_id = selected_sample.unique_id
				if (unique_test_id == eject_id)
					src.eject(selected_sample)
					return TRUE

		if(href_list["merge"])
			var/merge_id = text2num(href_list["merge"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == merge_id)
					active_sample = selected_sample
					menu_state = MENU_MERGE
					return TRUE

		if(href_list["toggle_active"])
			var/unique_id = text2num(href_list["unique_id"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == unique_id)
					for(var/datum/genetics/mutation/target_mutation in selected_sample.genetics_holder.mutation_pool)
						if(target_mutation.key == href_list["toggle_active"])
							if(target_mutation.active)
								target_mutation.active = FALSE
							else
								target_mutation.active = TRUE
							return TRUE
			log_debug("Genetics_analyzer.topic(): toggle_active ended way too late.")

			return TRUE
		if(href_list["irradiate"])
			var/unique_id = text2num(href_list["unique_id"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == unique_id)
					active_mutation = selected_sample.genetics_holder.irradiate(selected_sample.genetics_holder.getMutation(href_list["irradiate"]))
					menu_state = MENU_PROCESSING
					SSnano.update_uis(src)
					sleep(50)
					menu_state = MENU_IRRADIATE_RESULT
					return TRUE
			log_debug("Genetics_analyzer.topic(): irradiate ended way too late.")

			return TRUE
		if(href_list["combine"])
			var/unique_id = text2num(href_list["unique_id"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == unique_id)
					active_sample = selected_sample
					var/datum/genetics/mutation/target_mutation = selected_sample.genetics_holder.getMutation(href_list["combine"])
					if(target_mutation)
						mutations_to_combine.addMutation(selected_sample.genetics_holder.removeMutation(target_mutation.key), TRUE)
					mutations_combining_count++
					menu_state = MENU_COMBINE
					return TRUE
			log_debug("Genetics_analyzer.topic(): irradiate ended way too late.")

			return TRUE
		if(href_list["purge"])
			var/unique_id = text2num(href_list["unique_id"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == unique_id)
					selected_sample.genetics_holder.removeMutation(href_list["purge"])
					return TRUE
		if(href_list["analyze"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == unique_id)
					active_sample = selected_sample
			
			return TRUE
	if(menu_state == MENU_MERGE)
		if(href_list["merge"])
			var/merge_id = text2num(href_list["merge"])
			for(var/obj/item/genetics/sample/selected_sample in sample_plates)
				if (selected_sample.unique_id == merge_id)
					for(var/datum/genetics/mutation/target_mutation in selected_sample.genetics_holder.mutation_pool)
						var/datum/genetics/mutation/new_mutation = target_mutation.copy()
						active_sample.genetics_holder.addMutation(new_mutation)
					selected_sample.genetics_holder.removeAllMutations()
					sample_plates -= selected_sample
					qdel(selected_sample)
					menu_state = MENU_PROCESSING
					SSnano.update_uis(src)
					sleep(50)
					menu_state = MENU_MAIN
					return TRUE
	if(menu_state == MENU_COMBINE)
		if(href_list["add"])
			mutations_to_combine.addMutation(active_sample.genetics_holder.removeMutation(href_list["add"]), TRUE)
			mutations_combining_count++
			return TRUE

		if(href_list["remove"])
			active_sample.genetics_holder.addMutation(mutations_to_combine.removeMutation(href_list["remove"]), TRUE)
			mutations_combining_count--
			return TRUE

		if(href_list["combine"])
			var/list/mutation_amount_pair = list()
			for(var/datum/genetics/mutation/target_mutation in mutations_to_combine.mutation_pool)
				mutation_amount_pair += list(list(target_mutation, target_mutation.count))
			menu_state = MENU_PROCESSING
			mutations_combining_count = 0
			SSnano.update_uis(src)
			sleep(50)
			active_mutation = mutations_to_combine.combine(mutation_amount_pair)

			active_sample.genetics_holder.addMutation(active_mutation)
			menu_state = MENU_COMBINE_RESULT

	return FALSE

/*
TODO Topics:

-Main menu-
	List of the genetics plates. Each plate has the following
	eject: eject a sample plate from the analyzer
	modify: go to a modify menu
	merge: go to the merge menu
	analyze: go to the analysis menu


*/
#undef MENU_MAIN
#undef MENU_MERGE
#undef MENU_COMBINE
#undef MENU_PROCESSING
#undef MENU_ANALYZE
#undef MENU_COMBINE_RESULT
#undef MENU_IRRADIATE_RESULT