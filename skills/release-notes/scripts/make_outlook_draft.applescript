-- Create an unsent Outlook draft from an HTML body file and a subject file.
--
-- Usage (prefer the make_outlook_draft.py wrapper, which explains failures):
--   osascript make_outlook_draft.applescript <subject.txt> <body.html>
--
-- Both files are read as UTF-8, so non-ASCII characters survive. The message is
-- created with no recipients and is never sent — the user finishes it in Outlook.
--
-- Outlook is launched first and given two minutes to answer, because the first
-- launch after a macOS or Outlook upgrade can outlast the default Apple Event
-- timeout. Every failure is re-raised as "outlook-draft <number>: <message>" so
-- osascript exits non-zero and the caller can map the Apple Event error number
-- (for example -1743, Automation permission denied) to a remedy.
--
-- Note: Outlook's `save` command expects a file destination and cannot be used
-- to store the message in Drafts; creating and opening the message is enough.

on run argv
	if (count of argv) is not 2 then
		error "usage: osascript make_outlook_draft.applescript <subject.txt> <body.html>" number 2
	end if

	set subjPath to item 1 of argv
	set bodyPath to item 2 of argv
	set subjText to read (POSIX file subjPath) as «class utf8»
	set htmlBody to read (POSIX file bodyPath) as «class utf8»

	try
		tell application "Microsoft Outlook" to launch
		with timeout of 120 seconds
			tell application "Microsoft Outlook"
				set newMsg to make new outgoing message with properties {subject:subjText, content:htmlBody}
				open newMsg
				activate
			end tell
		end timeout
	on error errMsg number errNum
		error ("outlook-draft " & errNum & ": " & errMsg) number errNum
	end try

	return "draft created: " & subjText
end run
