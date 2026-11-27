// Run through wscript.exe so the launcher itself does not open a console.
if (WScript.Arguments.Count() !== 2) {
    WScript.Quit(1);
}

var powershell = WScript.Arguments.Item(0);
var maintenance = WScript.Arguments.Item(1);
var command = '"' + powershell + '" -NoProfile -NonInteractive -File "' + maintenance + '" -Action update';

// Hide the child window and wait so Task Scheduler receives the script's exit code.
var shell = new ActiveXObject('WScript.Shell');
WScript.Quit(shell.Run(command, 0, true));
