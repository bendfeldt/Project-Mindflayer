-- Create an unsent Outlook draft from an HTML body file and a subject file.
--
-- Usage:
--   osascript make_outlook_draft.applescript <subject.txt> <body.html>
--
-- Both files are read as UTF-8, so non-ASCII characters survive. The message is
-- created with no recipients and is never sent — the user finishes it in Outlook.
--
-- Note: Outlook's `save` command expects a file destination and cannot be used
-- to store the message in Drafts; creating and opening the message is enough.

on run argv
	if (count of argv) is not 2 then
		return "usage: osascript make_outlook_draft.applescript <subject.txt> <body.html>"
	end if

	set subjPath to item 1 of argv
	set bodyPath to item 2 of argv
	set subjText to read (POSIX file subjPath) as «class utf8»
	set htmlBody to read (POSIX file bodyPath) as «class utf8»

	tell application "Microsoft Outlook"
		set newMsg to make new outgoing message with properties {subject:subjText, content:htmlBody}
		open newMsg
		activate
	end tell

	return "draft created: " & subjText
end run
