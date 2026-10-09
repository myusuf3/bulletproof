"""Generate slice4.jsonl from markup.

Markup:
  {wrong|right}       error; input uses wrong, outputs use right
  {wrong|right|alt}   error; out0 uses right, out1 uses alt
  <a|b>               optional variant (not an error); input+out0 use a, out1 uses b
"""
import json
import re
import sys

ERR = re.compile(r"\{([^{}|]*)\|([^{}|]*)(?:\|([^{}|]*))?\}")
VAR = re.compile(r"<([^<>|]*)\|([^<>|]*)>")

FIX = [
    ("Hi Marcus,\n\nThanks for sending over the updated contract. I {recieved|received} it this morning and {its|it's} mostly fine, but {their|there} are two clauses I'd like our legal team to review before we sign. Could we push the call to {Thursday.|Thursday?} I {dont|don't} want to rush this and end up {loosing|losing} a week later on revisions.\n\nBest,\nDana",
     ["email", "linebreaks", "dense"]),
    ("Quick update on the migration: the staging cluster is now running Kubernetes <1.30 and|1.30, and> all the smoke tests passed overnight. I'll start rolling the change out to production after lunch, one region at a time. If anything looks off in Grafana, ping me directly rather than opening a ticket, since {its|it's} faster. The rollback plan is documented in the runbook, and {Priyankas|Priyanka's} team is on standby until 6 p.m.",
     ["slack", "buried", "jargon", "names"]),
    ("This PR {fixs|fixes} the race condition in the session cache that was causing intermittent logouts.\n\nChanges:\n- Replace the shared map with a {syncronized|synchronized} store\n- Add a regression test that reproduces the bug under load\n- Remove the old retry wrapper, which {wasnt|wasn't} doing anything useful\n\nI tested this locally with 500 concurrent {sessoins|sessions} and {didnt|didn't} see a single failure. {Their|There} is one follow-up ticket in Jira for the metrics dashboard.",
     ["pr-description", "linebreaks", "bullets", "dense", "jargon"]),
    ("Hello Mr. Okafor,\n\nI wanted to let you know that the kitchen faucet has been leaking for about a week now. {Its|It's} gotten worse over the last few days, and {theres|there's} now water pooling under the sink. Could you send someone to take a {look.|look?} I'm home most evenings after six, and {your|you're} welcome to let yourself in if I'm not around. Thanks in {advanse|advance}.\n\nKind regards,\nSofia",
     ["landlord", "linebreaks", "dense"]),
    ("I am writing to express my interest in the Senior Product Designer {roll|role} at Lumen Health. Over the past six years, I have led design for {buisness|business} tools used by thousands of clinicians, and I {beleive|believe} my experience turning complex workflows into simple interfaces would be a strong fit for your team. In my current position at Northwind, I redesigned the scheduling flow, which cut booking errors by 40 percent. I am particularly drawn to {Lumens|Lumen's} focus on {accessability|accessibility}, and I would welcome the {oppurtunity|opportunity} to discuss how I could contribute.",
     ["cover-letter", "dense"]),
    ("Notes from Tuesday's planning meeting:\n- The team agreed to {priortize|prioritize} the onboarding fixes for the next sprint\n- Jamal will {right|write} up the proposal for the new billing page by Friday\n- We {discused|discussed} moving standup to 9:30, but no decision was made\n- {Its|It's} still unclear who owns the analytics migration\n- Next meeting: Tuesday, same time",
     ["meeting-notes", "linebreaks", "bullets", "medium"]),
    ("Most people think of sourdough as a difficult bread, but the process is mostly waiting. You mix the dough, let it rest, fold it a few times, and then leave it alone overnight. The starter does the real work, slowly fermenting the flour and giving the bread {it's|its} sour flavor. The hardest part is learning to read the dough instead of the clock, since temperature and humidity change everything. Once you get a feel for it, you'll find it {alot|a lot} easier than it looks.",
     ["blog", "buried"]),
    ("We're excited to announce that dark mode is finally here! Starting today, you can switch themes from the Settings menu, and the app will remember {you're|your} choice across devices. We've also {improoved|improved} search, so results now load faster {then|than} before. A few users reported that notifications {where|were} arriving late on Android; that bug is fixed in version 4.2. As always, thanks for all the {feeback|feedback}.",
     ["product-update", "dense"]),
    ("hey, just a heads up that the deploy pipeline is {broked|broken} again. looks like the docker cache got {corupted|corrupted} after last night's upgrade. i'm rebuilding it now, should be back in twenty minutes or so. {definately|definitely} don't merge anything to main until i give the all clear",
     ["slack", "lowercase-style", "medium"]),
    ("Hi Rachel, I'd like to request PTO from March 14 to March 18 for a family wedding. I've already talked to Ben, and he's agreed to cover my on-call shift in PagerDuty that week. All of my open tickets should be {wraped|wrapped} up by the 12th, and I'll leave detailed handoff notes in Notion for anything that {isnt|isn't} finished. Please let me know if {thats|that's} okay or if {theirs|there's} anything else you need from me.",
     ["email", "medium", "jargon", "names"]),
    ("Morning everyone. The new reports {is|are} ready for review in the shared drive. Each of the regional managers {have|has} been sent a copy, and the deadline for comments is Friday at noon. {Me and Lena|Lena and I} will consolidate the feedback over the weekend. If you {cant|can't} open the file, let me know.",
     ["teams", "grammar", "medium"]),
    ("This change adds rate limiting to the public search endpoint. Requests are now capped at 100 per minute per API key, and anything over the limit receives a 429 with a Retry-After header. The limiter uses <Redis so|Redis, so> it works across all of our pods, and the threshold is configurable through an environment variable. I {seperated|separated} the middleware into its own package to keep the handler code readable. Load testing showed no measurable {affect|effect} on p99 latency.",
     ["pr-description", "buried", "jargon"]),
    ("Hi Karen, I hope {your|you're} doing well. I'm writing because the heater in the bedroom stopped working on Sunday night, and {its|it's} been very cold in the apartment since. I tried resetting the breaker like you {sugested|suggested}, but it {didnt|didn't} help. Would it be possible to have someone come by this {weak|week}? I {would of|would have|would've} fixed it myself, but I {dont|don't} want to {brake|break} anything.",
     ["landlord", "dense"]),
    ("The quarterly security audit wrapped up last week. Overall, the results were positive: no critical findings, and only three medium-severity issues, all of which are related to outdated dependencies. The infrastructure team has already patched two of them, and the third is scheduled for next {Wendesday|Wednesday}. We also rotated all service account credentials in Okta as a precaution. The full report is available on Confluence for anyone {whose|who's} interested.",
     ["status-update", "buried", "jargon"]),
    ("During my three years at Brightline Logistics, I managed a team of five analysts and built the forecasting models that our operations group still {relys|relies} on today. I am comfortable presenting to executives, and I take pride in explaining technical results in plain {langauge|language}. I was excited to see that your company is expanding {it's|its} analytics function, and I would love the chance to help {built|build} it.",
     ["cover-letter", "medium"]),
    ("<@Priyanka the|@Priyanka, the> Terraform plan for the new VPC looks good to me, but I noticed {to|two} things. First, the NAT gateway is only in one availability zone, which means we'd lose outbound traffic if that zone goes down. Second, the security group allows SSH from {anywere|anywhere}, which I'm pretty sure {wasnt|wasn't} intended. Can you tighten that to the VPN range before we {apply.|apply?} Otherwise {its|it's} ready to merge.",
     ["slack", "medium", "jargon", "names"]),
    ("Just a reminder that {expence|expense} reports for September are due by the end of the week. Last month {alot|a lot} of reports came in late. Please make sure every receipt is {attatched|attached} and that the project code is filled in correctly. Reports without codes {gets|get} sent back, which slows down {everyones|everyone's} reimbursement. If {your|you're} not sure which code to use, check the list in the finance channel or ask Tomás.",
     ["email", "dense", "names"]),
    ("The design review went well overall. Everyone agreed the new navigation is clearer, though Sam raised a concern that the settings icon is too easy to miss on smaller screens. We decided to run a quick usability test with five participants before committing to the change. Hana will recruit participants through the research panel and {shedule|schedule} sessions for next week. The results should be ready in time for the steering committee {meating|meeting} on the 21st.",
     ["meeting-notes", "buried", "names"]),
    ("Release notes for version 2.8:\n- Added support for exporting reports as CSV files\n- Fixed a bug where the {calender|calendar} view {would'nt|wouldn't} load for some users\n- Improved {perfomance|performance} on large projects\n- The sidebar now remembers {it's|its} collapsed state\n- Updated translations for French, German, and {Japenese|Japanese}",
     ["product-update", "linebreaks", "bullets", "dense"]),
    ("We placed an order for twelve standing desks on August 30 (order #48213), but only nine have been {recieved|received} so far. Could you please check on the status of the remaining {three.|three?} Our team is moving into the new office on Monday, so we would really appreciate an update as soon as {possable|possible}. If the desks {wont|won't} arrive in time, we may need to cancel part of the order.",
     ["email", "medium"]),
    ("When I first started running, I made {alot|a lot} of mistakes. I bought expensive shoes before I knew {weather|whether} I'd stick with it, and I tried to run {to|too} far, {to|too} fast, {to|too} soon. <Within a month I|Within a month, I> had shin splints and {could'nt|couldn't} run at all. Looking back, the {advise|advice} I needed was simple: slow down and be patient. {Your|You're} body needs time to adapt, and there's no shortcut for that.",
     ["blog", "dense", "homophones"]),
    ("Heads up: we got paged at 2:14 a.m. for elevated error rates on the checkout service. The root cause was a bad config push that pointed the service at the old Postgres replica. I rolled it back by 2:40, and error rates returned to normal within a few minutes. {Their|There} was no data loss, but about 300 orders failed and will need to be retried. I'll write up the postmortem in Notion {tommorow|tomorrow} morning.",
     ["slack", "buried", "jargon"]),
    ("Thank you for meeting with us yesterday, Mr. Delgado. We really {appriciated|appreciated} the chance to walk through your goals for the new site. As discussed, we'll send over a {proposel|proposal} by Friday that includes a timeline and two pricing options. In the meantime, could you share {you're|your} brand guidelines and any existing {photography.|photography?} It would help us {alot|a lot} with the early mockups.",
     ["email", "dense", "names"]),
    ("Summary: migrates the notification worker from the legacy queue to SQS.\n\n- Messages are now {proccessed|processed} in batches of ten\n- Failed messages are {retryed|retried} three times before going to the dead-letter queue\n- The old queue will stay online for a week in case we need to roll back\n\n{Its|It's} been running in staging since Monday with no {isues|issues}.",
     ["pr-description", "linebreaks", "bullets", "medium", "jargon"]),
    ("I'm happy to share that Daniela Cruz is joining the platform team as a staff engineer starting next Monday. Daniela spent the last five years at Stripe, where she led the effort to move their billing systems onto Kubernetes. She'll be focusing on our deployment tooling, which has been on {are|our} wish list for months. Please join me in welcoming her, and feel free to reach out if you'd like to grab a {coffe|coffee} with her during her first week.",
     ["announcement", "buried", "names", "jargon"]),
    ("I'm writing to give my 60-day notice that I'll be moving out of unit 3B at the end of {Febuary|February}. {Its|It's} been a pleasure renting from you, and I {apreciate|appreciate} how quickly you've always handled repairs. Please let me know when you'd like to schedule the final walkthrough, and where I should send my forwarding address for the security {deposite|deposit}.",
     ["landlord", "medium"]),
    ("Hey all, the sprint retro is moved to {thursday|Thursday} at 3. A few people {has|have} asked {weather|whether} we can do it async this time, but I think {its|it's} worth meeting in person since {alot|a lot} happened this sprint. Please add your notes to the board before the meeting so we {dont|don't} spend the first twenty minutes writing sticky notes.",
     ["teams", "dense"]),
    ("Tomatoes are one of the easiest vegetables to grow at home, as long as they get enough sun. Aim for at least six hours of direct light a day, and water deeply a few times a week rather than a little every day. Shallow watering encourages shallow roots, which makes the plants more {sensative|sensitive} to heat. Once the first fruits appear, {its|it's} a good idea to add a layer of mulch to keep the soil moist.",
     ["blog", "buried"]),
    ("As a recent graduate from the University of Toronto, I am eager to begin my career as a software {enginer|engineer}. During my final year, I {build|built} a scheduling app for a local nonprofit that {are|is} still used by {there|their} volunteers today. I also completed an internship at Shopify, {were|where} I worked on the checkout team and wrote tests for the payments flow. I am a fast learner, and I enjoy working {collaborativly|collaboratively} with designers and product managers. I would welcome the chance to {disscuss|discuss} how I can contribute to your team.",
     ["cover-letter", "dense", "names"]),
    ("Quick summary of what's left before launch:\n- Finish the pricing page copy (Alex)\n- Fix the broken links in the {foooter|footer} (Jun)\n- Get final sign-off from legal on the privacy policy\n- Load test the signup flow {incase|in case} {theres|there's} a traffic spike\n\nIf I missed anything, add it {hear|here}.",
     ["slack", "linebreaks", "bullets", "medium", "names"]),
    ("Thanks for reaching out, Jordan, and {Im|I'm} sorry for the trouble with your subscription. I've looked into your account, and it looks like you {where|were} charged twice on October 2 due to a processing error on our end. I've {all ready|already} issued a refund for the duplicate charge, which should appear on your statement within five to seven {buisness|business} days. Please don't hesitate to reply if {theres|there's} anything else I can help with.",
     ["email", "support", "dense"]),
    ("In today's sync, we reviewed the Q4 roadmap and agreed to cut the reporting dashboard from scope. The data team doesn't have capacity until January, and the feature depends on a pipeline that hasn't been built yet. Instead, we'll focus on improving the mobile onboarding flow, which has the highest drop-off rate in our funnel. Kenji will share updated {estimats|estimates} by Monday, and we'll revisit the {dashbord|dashboard} in the new year.",
     ["meeting-notes", "buried", "names"]),
    ("This month we focused on {stablity|stability}. The team fixed over forty bugs, including a crash that {occured|occurred} when users uploaded large images on older iPhones. We also reduced the {apps|app's} startup time by almost half, which should make a {noticable|noticeable} difference for people on slower {conections|connections}. Next month, {were|we're} turning our attention to the long-requested offline mode.",
     ["product-update", "dense"]),
    ("I owe you an apology for missing our call this morning, Simone. I had it on my calendar in the wrong time zone and {didnt|didn't} realize until it was {to|too} late. {Its|It's} completely on me. I know your schedule is tight this week, so I {completly|completely} understand if we need to push it to next month. Would any time Thursday afternoon {work.|work?}",
     ["email", "medium", "names"]),
    ("This PR removes the deprecated v1 export endpoints, which haven't received any traffic in the last ninety days according to Datadog. I've also deleted the related feature flags and cleaned up the test fixtures that referenced them. The public API docs have been updated {accordinly|accordingly}. Reviewers should pay special attention to the routing changes in server.go, since that file {effects|affects} every request.",
     ["pr-description", "buried", "jargon"]),
    ("ok so i {finaly|finally} figured out why the build was slow. the test suite was {spining|spinning} up a new database for every single test file instead of {reuseing|reusing} one. i changed it to share a single <instance and now|instance, and now> the whole thing runs in about four minutes instead of twelve. going to open a pr after lunch, would {apreciate|appreciate} a review from someone who knows the fixtures code",
     ["slack", "lowercase-style", "medium"]),
    ("Thank you for reaching out about the data engineering position, Laura. I'm {definately|definitely} interested and would be happy to set up a call. I'm available most afternoons this week, {accept|except} for Wednesday. Could you also send me more details about the team and the {interveiw|interview} {process.|process?} I'd like to {prepair|prepare} as much as possible {before hand|beforehand}.",
     ["email", "dense", "names"]),
    ("I used to keep my to-do list in my head, which worked fine until it {did'nt|didn't}. Now I write everything down in a plain text file at the start of each day. The list isn't fancy, but it forces me to decide what actually matters before the day gets away from me. The {affect|effect} has been surprising: I finish more, and I worry less about the things I {havent|haven't} gotten to. {Its|It's} a small habit, but it's changed how I work.",
     ["blog", "medium"]),
    ("Hi all, a quick update from the data platform side. The nightly ETL jobs have been moved from Airflow to Dagster, and so far everything has run on schedule. Dashboards in Looker should look exactly the same, but if you see any numbers that seem off, please let Priyanka or me know. We'll keep the old Airflow jobs running in parallel {untill|until} the end of the month, just in case. {Thank's|Thanks} for your patience during the migration.",
     ["teams", "buried", "jargon", "names"]),
    ("Hi Mr. Brennan,\n\nHere are the issues I noticed during the move-in {inspecton|inspection}:\n- The bathroom fan {does'nt|doesn't} turn on\n- {Theres|There's} a crack in the living room window\n- Two of the kitchen cabinet doors are {lose|loose}\n- The smoke detector in the hallway is missing {it's|its} battery\n\nI've attached photos of each one. Please let me know when someone can come take a look.\n\nThanks,\nAisha",
     ["landlord", "linebreaks", "bullets", "dense"]),
    ("What draws me to this role is the chance to work on tools that teachers actually use every day. Before moving into product management, I spent four years teaching middle school math, so I know firsthand how much time gets lost to clunky software. At Classwise, I led the redesign of the gradebook, which reduced the time {teacher's|teachers} spent entering grades by nearly a third. I'd love the chance to discuss how my background {compliments|complements} your roadmap.",
     ["cover-letter", "buried"]),
    ("I wanted to follow up on {are|our} conversation from last week about the {vender|vendor} contract. After reviewing the numbers again, I think we're paying {to|too} much for support hours we rarely use. {Theres|There's} probably room to {negociate|negotiate} a lower rate, {especialy|especially} since we've been customers for four years. Do you want me to draft a proposal before the renewal {date.|date?}",
     ["email", "dense"]),
    ("<FYI the|FYI, the> Jira board for the mobile team has been reorganized. Epics are now grouped by quarter {in stead|instead} of by feature, and {there|their} child tickets should all be linked correctly. If anything looks missing, check the {archieve|archive} column first.",
     ["slack", "medium", "jargon"]),
    ("This PR moves the onboarding emails onto the new {templete|template} system.\n\nWhat changed:\n- The welcome email now {pull's|pulls} the user's first name from {there|their} profile\n- Removed the hard-coded links, which {where|were} pointing to the old domain\n- Added snapshot tests for all four emails\n\nI {havent|haven't} touched the unsubscribe logic yet. {Thats|That's} coming in a separate PR.",
     ["pr-description", "linebreaks", "bullets", "dense"]),
    ("Lisbon {surprized|surprised} me in the best way. I expected beautiful tiles and good food, but I {wasnt|wasn't} prepared for how hilly the city is. By the second day, my legs {was|were} sore from climbing the steep streets of Alfama. The trams helped, although {their|they're} usually packed with tourists. If you go, bring {comfterable|comfortable} shoes and plan on {alot|a lot} of walking.",
     ["blog", "dense", "names"]),
    ("Action items from the vendor review:\n- Elena will request updated pricing from all three vendors\n- Marcus will check whether the current contract has an early termination fee\n- The team will score each vendor against the criteria in the shared {spreadsheat|spreadsheet}\n- Final recommendation is due to leadership by October 20\n\nWe'll meet again next {Teusday|Tuesday} to compare notes.",
     ["meeting-notes", "linebreaks", "bullets", "buried", "names"]),
    ("Hey team, I'm feeling pretty sick <today so|today, so> I'm going to log off and rest. I {wont|won't} be checking Slack, but my phone is on if something urgent comes up. Sanjay has kindly agreed to cover my code {reveiws|reviews}. Sorry for the short notice, and {hopefuly|hopefully} I'll be back {tommorow|tomorrow}.",
     ["slack", "medium", "names"]),
    ("Starting next Monday, we're switching our design handoff process from Zeplin to Figma's Dev Mode. Engineers will be able to inspect spacing, colors, and assets directly in the Figma file, so there's no need to export anything separately. I've set up a short training session on Wednesday at 11 a.m. for anyone who {hasnt|hasn't} used Dev Mode before. Please bring {you're|your} questions.",
     ["email", "buried", "jargon"]),
    ("I have spent the past decade working in hospitality, most recently as the general manager of a 120-room hotel in Halifax. <In that role I|In that role, I> {overseen|oversaw} a staff of forty and {consistantly|consistently} ranked among the top three properties in our region for guest satisfaction. I'm now looking to bring that experience to a corporate events team, {were|where} attention to detail and calm under pressure {is|are} just as important. I {beleive|believe} my background makes me a strong candidate for this position.",
     ["cover-letter", "dense", "grammar"]),
    ("Starting this week, workspace admins can require two-factor authentication for every member of their team. Once the setting is enabled, anyone who hasn't set up 2FA will be prompted to do so the next time they sign in. Members can use any standard authenticator app, or a hardware key if their organization {suports|supports} it. We {recomend|recommend} turning this on for all workspaces that store customer data.",
     ["product-update", "buried"]),
    ("Hey, does anyone know {weather|whether} the office is open on {monday|Monday}? I {herd|heard} {its|it's} closed for the holiday, but the calendar still {show's|shows} it as a normal workday. I {dont|don't} want to come in and find the doors locked. If {your|you're} going in, let me know and maybe we can carpool.",
     ["slack", "dense", "homophones"]),
    ("Just letting you know that I sent this month's rent through e-Transfer this morning, Dave. The bank flagged it for review, so it might take an extra day to {arive|arrive}. Sorry for any {inconvience|inconvenience}! Let me know if it {doesnt|doesn't} come through by Friday.",
     ["landlord", "medium"]),
    ("Code review is less about catching bugs than about sharing context. When I review a pull request, I'm mostly trying to understand why the change was made and whether it fits with the rest of the system. Bugs do get caught, of course, but the bigger payoff is that two people now understand the code instead of one. That redundancy pays off the first time someone is on vacation and {there|their} feature breaks in production. It's also the cheapest form of mentorship I know of, especially for newer engineers who {arent|aren't} sure what good looks like yet.",
     ["blog", "buried"]),
    ("Hi Priyanka, I took a look at the Q3 numbers you shared. The revenue figures look right, but the churn rate on slide 4 {doesnt|doesn't} match what I'm seeing in Salesforce. I think the {discrepency|discrepancy} might be {becuase|because} the deck counts paused accounts as churned. Can we go over it together before {tommorow's|tomorrow's} review?",
     ["teams", "linebreaks", "medium", "names", "jargon"]),
    ("This change {adress|addresses} the memory leak in the image processing worker. The worker was holding onto references to every {proccessed|processed} file, so memory usage grew {untill|until} the pod got OOM-killed. I {refactered|refactored} the loop so each buffer is released after {it's|its} upload completes. Memory now stays flat at around 300 MB {through out|throughout} a full run. {Their|There} are still a few optimizations we could make, but I'd rather ship this fix first.",
     ["pr-description", "dense", "jargon"]),
    ("We met with the {accessability|accessibility} consultant on Thursday to go over the audit results. Most of the issues were minor, like missing alt text and low contrast on some buttons, but the checkout form has a few serious problems. Screen readers {cant|can't} announce the error messages, and keyboard focus gets {traped|trapped} in the date picker. We've agreed to fix the checkout issues before {any thing|anything} else, since they block purchases.",
     ["meeting-notes", "medium"]),
    ("PagerDuty rotations for November are posted. I tried to balance it so nobody has more than one weekend shift, and I swapped Felipe and Grace in week two since Felipe is traveling. If you need to trade a shift, please arrange it with someone directly and then update the schedule yourself. {Its|It's} important that the schedule stays accurate so alerts don't go to the wrong {persion|person}.",
     ["slack", "buried", "jargon", "names"]),
    ("I've attached the {invoise|invoice} for the website work completed in September, Tom. As agreed, the total includes the additional landing page you requested mid-month. Payment is due {with in|within} thirty days. I {realy|really} enjoyed working on this project, and I'd be glad to help with the {maintainance|maintenance} work you {mentionned|mentioned} for next quarter. Let me know {weather|whether} you'd like a quote.",
     ["email", "dense"]),
    ("Hosting a dinner party doesn't have to be stressful. The trick is to pick a menu where most of the work happens before {you're|your} guests arrive. A braise or a big pot of soup is perfect, because it gets better as it sits. Make dessert the day before, set the table in the afternoon, and leave yourself {atleast|at least} half an hour to relax. {Noone|No one} will remember if the napkins {didnt|didn't} match.",
     ["blog", "medium"]),
    ("Standup notes for {wenesday|Wednesday}:\n- Yesterday I {finshed|finished} the API changes for the export feature\n- Today I'm {writting|writing} tests and {updateing|updating} the docs\n- Blocked: the staging {enviroment|environment} is down again, so I can't run the integration tests\n- Pairing with Ines this afternoon on the flaky checkout test",
     ["slack", "linebreaks", "bullets", "dense"]),
    ("I am excited to apply for the Marketing Coordinator position at Fernwood Books. As a lifelong reader and a former bookstore employee, I understand how much a good recommendation can mean to a {costumer|customer}. In my current role at a small digital agency, I manage social media {acounts|accounts} for six clients and have grown {there|their} combined following by over 50 percent. I am confident that my {experiance|experience} and enthusiasm would make me a {valueable|valuable} addition to {you're|your} team.",
     ["cover-letter", "dense"]),
    ("Thanks for putting together the onboarding guide for new hires, Hannah. I read through the whole thing last night, and it's a huge improvement over what we had before. The section on setting up local development is especially clear. My only suggestion would be to add a short note about requesting VPN {acess|access}, since that {usualy|usually} takes a couple of days to get approved.",
     ["email", "buried", "names"]),
    ("Our new integration with Slack lets you get notified the moment a customer replies to a ticket. You can choose {witch|which} channels receive alerts and filter them by priority, so your team {isnt|isn't} {overwelmed|overwhelmed} by noise. To get started, head to Settings, then Integrations, and click Connect next to the Slack logo. Setup takes less {then|than} a minute.",
     ["product-update", "medium"]),
    ("I spent some time this afternoon looking into why the search results feel slow on the dashboard. It turns out we're making three separate API calls when the page loads, and the last one waits for the first two to finish before it starts. If we batch them into a single request, we should be able to cut the load time roughly in half. I've sketched out the change in a draft PR, but I'd like a second {opinon|opinion} from someone on the backend team before I {procede|proceed}.",
     ["slack", "buried"]),
    ("Thanks for covering for me at {yesterdays|yesterday's} client meeting. I heard it went well and that {their|they're} {exited|excited} about the new proposal. I {definately|definitely} owe you one! When you get a chance, could you send me {you're|your} notes? I want to make sure I understand exactly what we promised them before I start on the estimate. Also, did they say anything about the budget, or is that still up in the {air.|air?} Let's grab lunch next week. {Its|It's} on me.",
     ["email", "dense", "homophones"]),
    ("Summary of the hiring committee discussion: all four interviewers {recomended|recommended} moving forward with the candidate for the backend role. {There|Their} system design answer was the strongest we've seen this cycle. The only concern was limited experience with Go, but the team felt {its|it's} something they can pick up quickly. Kwame will send the offer by the end of the week.",
     ["meeting-notes", "medium", "names"]),
    ("{Its|It's} easy to underestimate how much sleep {effects|affects} your mood. <For years I|For years, I> told {my self|myself} I could get by on five or six hours. Then I started tracking my sleep, and the pattern was {obvous|obvious}: on days after a short night, I was {irritible|irritable}, distracted, and {alot|a lot} less patient with the people around me. Now I treat bedtime like a meeting I {cant|can't} skip.",
     ["blog", "dense"]),
    ("Reminder: the office will be closed on Monday for Thanksgiving. A few things to {remmember|remember}:\n- Anyone on call should make sure {there|their} laptop is charged and VPN is working\n- Please take {you're|your} food out of the fridge by Friday, since the kitchen is being cleaned over the weekend\n- Building access cards will still work if you need to come in\n\nEnjoy the long weekend!",
     ["announcement", "linebreaks", "bullets", "medium"]),
    ("Thanks again for taking the time to speak with me on Friday. I really enjoyed learning about how your team approaches research, especially the way you involve engineers in customer interviews from the very beginning. It's rare to see that level of collaboration, and it made me even more excited about the role. As promised, I've attached the case study we {dicussed|discussed}, which walks through how we redesigned the claims process at my current company. Please let me know if you have any questions or if {their|there} is anything else I can provide.",
     ["email", "buried"]),
    ("Hey {every one|everyone}, just a reminder that {tommorow|tomorrow} is the last day to submit {you're|your} self-reviews. {Alot|A lot} of people {havent|haven't} started yet, so please {dont|don't} leave it {untill|until} the last minute. The form {take's|takes} about twenty minutes, and {its|it's} linked in the HR channel. If you {run in to|run into} any problems, message Jess or me.",
     ["slack", "dense", "very-dense"]),
]

CLEAN = [
    ("Hi Sam, I've reviewed the draft budget for next quarter, and it looks solid overall. The only line I'd question is the travel estimate, which seems high given that most of our client meetings are now virtual. Could we trim it by about a third and move the difference into the training budget? Let me know what you think before Thursday's finance review.",
     ["email"]),
    ("heads up, the staging database is getting restored from last night's snapshot, so anything you pushed after midnight will be gone. should be back up in about thirty minutes. if you need anything from before the snapshot, ping me and i can pull it from the backup bucket. i'll post here when it's ready.",
     ["slack", "lowercase-style"]),
    ("This PR adds pagination to the audit log endpoint.\n\n- Results are returned in pages of 50 by default\n- Clients can pass a cursor to fetch the next page\n- The response format is unchanged for the first page\n\nI've updated the API docs and added tests for empty and partial pages.",
     ["pr-description", "linebreaks", "bullets"]),
    ("Dear Mr. Alvarez,\n\nThank you for fixing the dishwasher so quickly last week. It's been working perfectly since the repair. I also wanted to mention that the lock on the building's side door has been sticking, and it sometimes takes a few tries to open. It might be worth having someone look at it before winter.\n\nBest regards,\nChloe",
     ["landlord", "linebreaks"]),
    ("In my five years as a nurse in a busy emergency department, I learned to stay calm, communicate clearly, and make decisions quickly with incomplete information. Those same skills drew me to clinical informatics, where I now help hospitals design systems that fit the way nurses actually work. I would be glad to bring that perspective to your team at Meridian Health.",
     ["cover-letter"]),
    ("Decisions from today's architecture review:\n- We'll keep the monolith for now and revisit splitting out billing in Q2\n- Kubernetes upgrades will move to a quarterly schedule\n- Priyanka will own the new incident review process in PagerDuty\n- The platform team will draft an ADR for the new caching layer by next Friday",
     ["meeting-notes", "linebreaks", "bullets", "jargon", "names"]),
    ("There's a particular kind of quiet that settles over a city early on a Sunday morning. The streets are mostly empty, the cafés are just starting to open, and even the buses seem to move more slowly. I've started taking long walks at that hour, partly for the exercise and partly because it's the only time I can hear myself think.",
     ["blog"]),
    ("Version 3.4 is rolling out to all users this week. The biggest change is a faster editor: documents with thousands of lines now open almost instantly, and scrolling stays smooth even with syntax highlighting turned on. We've also fixed the issue where comments occasionally disappeared after a sync. Thanks to everyone who sent in detailed bug reports; they made a huge difference.",
     ["product-update"]),
    ("Hi everyone, the quarterly all-hands has moved from Thursday to Friday at 10 a.m. because of a conflict with the board meeting. The agenda hasn't changed, and the Zoom link in the original invite will still work. If you can't attend live, a recording will be posted in the usual channel by the end of the day.",
     ["teams"]),
    ("Hi Priyanka, thanks for flagging the issue with the Jira automation. I looked into it, and the rule was firing twice because it was attached to both the project and the global workflow. I've removed the duplicate, so you should only get one notification per ticket from now on. Let me know if you see it happen again.",
     ["email", "jargon", "names"]),
]


def render(markup):
    inp = VAR.sub(lambda m: m.group(1), ERR.sub(lambda m: m.group(1), markup))
    out0 = VAR.sub(lambda m: m.group(1), ERR.sub(lambda m: m.group(2), markup))
    out1 = VAR.sub(lambda m: m.group(2), ERR.sub(lambda m: m.group(3) or m.group(2), markup))
    errors = [f"{m.group(1)} -> {m.group(2)}" for m in ERR.finditer(markup)]
    return inp, out0, out1, errors


def main(path):
    rows = []
    for i, (markup, tags) in enumerate(FIX, 1):
        inp, out0, out1, errors = render(markup)
        outs = [out0] if out1 == out0 else [out0, out1]
        rows.append({"id": f"s4-{i:03d}", "input": inp,
                     "expected": {"kind": "fix", "acceptableOutputs": outs},
                     "errors": errors, "tags": ["paragraph"] + tags})
    for j, (text, tags) in enumerate(CLEAN, len(FIX) + 1):
        assert "{" not in text and "<" not in text
        rows.append({"id": f"s4-{j:03d}", "input": text,
                     "expected": {"kind": "unchanged"}, "errors": [],
                     "tags": ["clean", "paragraph"] + tags})
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
