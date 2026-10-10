import json, re, sys

FIX = [
("I'll send teh report over before lunch tomorrow.", "I'll send the report over before lunch tomorrow.", ["teh -> the"]),
("Did you recieve the invoice I sent on Monday?", "Did you receive the invoice I sent on Monday?", ["recieve -> receive"]),
("We definately need to book the room before Friday.", "We definitely need to book the room before Friday.", ["definately -> definitely"]),
("Please keep the receipts seperate from the personal ones.", "Please keep the receipts separate from the personal ones.", ["seperate -> separate"]),
("The outage occured right after the deploy finished.", "The outage occurred right after the deploy finished.", ["occured -> occurred"]),
("can you accomodate two more people at dinner tonight?", "can you accommodate two more people at dinner tonight?", ["accomodate -> accommodate"]),
("i dont think the train is running today", "i don't think the train is running today", ["dont -> don't"]),
("Thats exactly what I was worried about.", "That's exactly what I was worried about.", ["Thats -> That's"]),
("Im running about ten minutes late, sorry!", "I'm running about ten minutes late, sorry!", ["Im -> I'm"]),
("We had alot of feedback on the new onboarding flow.", "We had a lot of feedback on the new onboarding flow.", ["alot -> a lot"]),
("I some times forget to water the plants on weekends.", "I sometimes forget to water the plants on weekends.", ["some times -> sometimes"]),
("The meeting has been moved to Thrusday afternoon.", "The meeting has been moved to Thursday afternoon.", ["Thrusday -> Thursday"]),
("Could you double-check the numbers in the budget spreadhseet?", "Could you double-check the numbers in the budget spreadsheet?", ["spreadhseet -> spreadsheet"]),
("Thanks for your patience while we look into thw isssue.", "Thanks for your patience while we look into the issue.", ["thw -> the", "isssue -> issue"]),
("The new hire starts next week and will need a laptop, a badge, and acess to the shared drive.", "The new hire starts next week and will need a laptop, a badge, and access to the shared drive.", ["acess -> access"]),
("Let me know if you have any questoins about the proposal.", "Let me know if you have any questions about the proposal.", ["questoins -> questions"]),
("She was embarassed when her phone rang during the presentation.", "She was embarrassed when her phone rang during the presentation.", ["embarassed -> embarrassed"]),
("Our goverment contact said the permit should arrive by the end of the month.", "Our government contact said the permit should arrive by the end of the month.", ["goverment -> government"]),
("Its been a long week, so Im heading home early.", "It's been a long week, so I'm heading home early.", ["Its -> It's", "Im -> I'm"]),
("I beleive the shipment will arrive tommorow morning.", "I believe the shipment will arrive tomorrow morning.", ["beleive -> believe", "tommorow -> tomorrow"]),
("The resturant was closed, so we ended up getting pizza insted.", "The restaurant was closed, so we ended up getting pizza instead.", ["resturant -> restaurant", "insted -> instead"]),
("Pleasr make sure the contracts are signed before you leave the office.", "Please make sure the contracts are signed before you leave the office.", ["Pleasr -> Please"]),
("we should probly leave soon if we want to beat the traffic", "we should probably leave soon if we want to beat the traffic", ["probly -> probably"]),
("I wasnt sure if you wanted the blue one or the green one.", "I wasn't sure if you wanted the blue one or the green one.", ["wasnt -> wasn't"]),
("They couldnt find a parking spot anywhere near the stadium.", "They couldn't find a parking spot anywhere near the stadium.", ["couldnt -> couldn't"]),
("Let me know when youre free to chat this week.", "Let me know when you're free to chat this week.", ["youre -> you're"]),
("Its a shame they didnt renew the lease on the old studio.", "It's a shame they didn't renew the lease on the old studio.", ["Its -> It's", "didnt -> didn't"]),
("The libary closes early on Sundays, so plan acordingly.", "The library closes early on Sundays, so plan accordingly.", ["libary -> library", "acordingly -> accordingly"]),
("I recomend we push the launch back by a week so we can wprk through the remaining bugs.", "I recommend we push the launch back by a week so we can work through the remaining bugs.", ["recomend -> recommend", "wprk -> work"]),
("Notes: follow up with vendor, confirm the shippping adress, update the calender.", "Notes: follow up with vendor, confirm the shipping address, update the calendar.", ["shippping -> shipping", "adress -> address", "calender -> calendar"]),
("We recieved your aplication and will be in touch within two weeks.", "We received your application and will be in touch within two weeks.", ["recieved -> received", "aplication -> application"]),
("Hey, are we still on for coffe tomorow?", "Hey, are we still on for coffee tomorrow?", ["coffe -> coffee", "tomorow -> tomorrow"]),
("The comittee will vote on the new policy at the next meeting.", "The committee will vote on the new policy at the next meeting.", ["comittee -> committee"]),
("I realy apreciate you covering my shift on such short notice.", "I really appreciate you covering my shift on such short notice.", ["realy -> really", "apreciate -> appreciate"]),
("Untill we hear back from legal, please dont share the draft with anyone outside the team.", "Until we hear back from legal, please don't share the draft with anyone outside the team.", ["Untill -> Until", "dont -> don't"]),
("The wether this weekend looks perfect for a hike.", "The weather this weekend looks perfect for a hike.", ["wether -> weather"]),
("I think we should definitly revisit the pricing page because its confusing for alot of new users.", "I think we should definitely revisit the pricing page because it's confusing for a lot of new users.", ["definitly -> definitely", "its -> it's", "alot -> a lot"]),
("Teh quick fix worked. We still need a permanant solution, though.", "The quick fix worked. We still need a permanent solution, though.", ["Teh -> The", "permanant -> permanent"]),
("Wierd, the build passed locally but failed on the server.", "Weird, the build passed locally but failed on the server.", ["Wierd -> Weird"]),
("I'll be out of the offfice from Monday through Wednesday.", "I'll be out of the office from Monday through Wednesday.", ["offfice -> office"]),
("Can you remind me what tiem the dentsit appointment is?", "Can you remind me what time the dentist appointment is?", ["tiem -> time", "dentsit -> dentist"]),
("The kids were so exicted about the trip to the aquarium.", "The kids were so excited about the trip to the aquarium.", ["exicted -> excited"]),
("Can you sned me the slides from this mornimg's meeting?", "Can you send me the slides from this morning's meeting?", ["sned -> send", "mornimg's -> morning's"]),
("i honestly cant beleive how fast this year went by", "i honestly can't believe how fast this year went by", ["cant -> can't", "beleive -> believe"]),
("We need to finalize the agenda, book a venue, and send out the invitaions by Friday.", "We need to finalize the agenda, book a venue, and send out the invitations by Friday.", ["invitaions -> invitations"]),
("The managment team agreed to the new schedule after a long discusion.", "The management team agreed to the new schedule after a long discussion.", ["managment -> management", "discusion -> discussion"]),
("Its not neccessary to bring anything, but snacks are always welcome.", "It's not necessary to bring anything, but snacks are always welcome.", ["Its -> It's", "neccessary -> necessary"]),
("I accidently deleted the file, but luckily there was a backup.", "I accidentally deleted the file, but luckily there was a backup.", ["accidently -> accidentally"]),
("I jist got home, so give me ten minutes to change.", "I just got home, so give me ten minutes to change.", ["jist -> just"]),
("The begining of the movie was slow, but the ending was increadible.", "The beginning of the movie was slow, but the ending was incredible.", ["begining -> beginning", "increadible -> incredible"]),
("Shes going to call you back once she gets out of her meeting.", "She's going to call you back once she gets out of her meeting.", ["Shes -> She's"]),
("Were there any isues with the release last night?", "Were there any issues with the release last night?", ["isues -> issues"]),
("We cant gaurantee delivery before the holidays, but well do our best.", "We can't guarantee delivery before the holidays, but we'll do our best.", ["cant -> can't", "gaurantee -> guarantee", "well -> we'll"]),
("Thier office is on the third floor, right next to the elevaters.", "Their office is on the third floor, right next to the elevators.", ["Thier -> Their", "elevaters -> elevators"]),
("I tried to explain the proccess, but I dont think it made much sense to them.", "I tried to explain the process, but I don't think it made much sense to them.", ["proccess -> process", "dont -> don't"]),
("The presentaion went well, and the client seemed genuinly interested in the next phase.", "The presentation went well, and the client seemed genuinely interested in the next phase.", ["presentaion -> presentation", "genuinly -> genuinely"]),
("Please let me know if theres anything else I can help with.", "Please let me know if there's anything else I can help with.", ["theres -> there's"]),
("Ive attached the revised contract for your reveiw.", "I've attached the revised contract for your review.", ["Ive -> I've", "reveiw -> review"]),
("The enviroment variables need to be set before you run the script.", "The environment variables need to be set before you run the script.", ["enviroment -> environment"]),
("The plan is to meet at the statoin at noon and then grab lunch near the musuem.", "The plan is to meet at the station at noon and then grab lunch near the museum.", ["statoin -> station", "musuem -> museum"]),
("I wasnt expecting such a sucessful turnout, but the event was completly packed and everyone seemed to have a grate time.", "I wasn't expecting such a successful turnout, but the event was completely packed and everyone seemed to have a great time.", ["wasnt -> wasn't", "sucessful -> successful", "completly -> completely", "grate -> great"]),
("Its definately worth the extra money if you plan to use it evrey day.", "It's definitely worth the extra money if you plan to use it every day.", ["Its -> It's", "definately -> definitely", "evrey -> every"]),
("The tehcnician said the repiar would take about three bussiness days.", "The technician said the repair would take about three business days.", ["tehcnician -> technician", "repiar -> repair", "bussiness -> business"]),
("Dont forget that the dealine for expense reports is this Friday at noon.", "Don't forget that the deadline for expense reports is this Friday at noon.", ["Dont -> Don't", "dealine -> deadline"]),
("Hi Sam, just a quick remider that the quartely review meetinf is scheduled for next Tuesday, so please have your slides ready by Monday evening if possible.", "Hi Sam, just a quick reminder that the quarterly review meeting is scheduled for next Tuesday, so please have your slides ready by Monday evening if possible.", ["remider -> reminder", "quartely -> quarterly", "meetinf -> meeting"]),
("Im not sure wich option is better, but Id lean toward the cheaper one for now.", "I'm not sure which option is better, but I'd lean toward the cheaper one for now.", ["Im -> I'm", "wich -> which", "Id -> I'd"]),
("The recipie calls for two cups of flour and a pinch of salt.", "The recipe calls for two cups of flour and a pinch of salt.", ["recipie -> recipe"]),
("Thanks agian for hosting us last weekend. We had a wonderfull time and the kids havent stopped talking about the pool.", "Thanks again for hosting us last weekend. We had a wonderful time and the kids haven't stopped talking about the pool.", ["agian -> again", "wonderfull -> wonderful", "havent -> haven't"]),
("Teh server went down at 3 a.m. and nobody noticed untill the morning standup. We definately need better alerting.", "The server went down at 3 a.m. and nobody noticed until the morning standup. We definitely need better alerting.", ["Teh -> The", "untill -> until", "definately -> definitely"]),
("We recieved alot of complaints about the new layout, so we're going to seperate the settings into two diffrent tabs untill the redesign is done.", "We received a lot of complaints about the new layout, so we're going to separate the settings into two different tabs until the redesign is done.", ["recieved -> received", "alot -> a lot", "seperate -> separate", "diffrent -> different", "untill -> until"]),
]

CLEAN = [
"I'll send the updated slides over before the end of the day.",
"heading out now, see you at the park in twenty",
"Thanks for the quick turnaround on the contract. Everything looks good on our end.",
"The hotel can accommodate everyone, but we'll need separate rooms for the two teams.",
"The meeting has been moved to Thursday afternoon, so please update your calendars.",
"Notes: confirm the shipping address, follow up with the vendor, and update the project timeline.",
"I didn't realize how late it was until the lights in the office turned off.",
"Let me know if you have any questions about the proposal or the budget.",
"We received a lot of helpful feedback, and the team is already working on the next version.",
"It's definitely worth the extra money if you plan to use it every day.",
]

def variants(fix):
    out = []
    def add(v):
        if v not in out and len(out) < 4:
            out.append(v)
    add(fix)
    if "'" in fix:
        add(fix.replace("'", "\u2019"))
    lower_start = fix[0].islower()
    cap = None
    if lower_start:
        cap = re.sub(r"\bi\b", "I", fix)
        cap = cap[0].upper() + cap[1:]
        add(cap)
    if fix[-1] not in ".!?":
        add(fix + ".")
        if cap:
            add(cap + ".")
    elif len(out) < 2:
        add(fix[:-1])
    return out

def tags_for(inp, errs):
    t = ["typo"]
    if any("'" in e.split(" -> ")[1] and "'" not in e.split(" -> ")[0] for e in errs):
        t.append("apostrophe")
    if any(e.split(" -> ")[0].count(" ") != e.split(" -> ")[1].count(" ") for e in errs):
        t.append("word-split")
    if len(errs) > 1:
        t.append("multi-error")
    if inp[0].islower():
        t.append("lowercase-style")
    if len(re.findall(r"[.!?](\s|$)", inp)) > 1:
        t.append("two-sentence")
    return t

assert len(FIX) == 70 and len(CLEAN) == 10, (len(FIX), len(CLEAN))
lines = []
for i, (inp, fix, errs) in enumerate(FIX, 1):
    for e in errs:
        w, r = e.split(" -> ")
        assert re.search(r"(?<!\w)" + re.escape(w) + r"(?!\w)", inp), (i, w)
        assert r in fix, (i, r)
    # applying every error must produce the fix exactly
    applied = inp
    for e in errs:
        w, r = e.split(" -> ")
        applied = re.sub(r"(?<!\w)" + re.escape(w) + r"(?!\w)", r, applied, count=1)
    assert applied == fix, (i, applied, fix)
    lines.append({"id": f"s1-{i:03d}", "input": inp, "expected": {"kind": "fix", "acceptableOutputs": variants(fix)}, "errors": errs, "tags": tags_for(inp, errs)})
for j, inp in enumerate(CLEAN, 71):
    lines.append({"id": f"s1-{j:03d}", "input": inp, "expected": {"kind": "unchanged"}, "errors": [], "tags": ["clean"]})

with open(sys.argv[1], "w") as f:
    for o in lines:
        f.write(json.dumps(o, ensure_ascii=False) + "\n")
