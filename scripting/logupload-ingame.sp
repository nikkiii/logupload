#include <logupload>

#define PLUGIN_VERSION	"0.1"

new String:g_sLogUrl[128];

public Plugin:myinfo = {
	name = "LogUpload In-Game Viewing",
	author = "Nikki",
	description = "Adds sm_logs (!logs and /logs too) and '.ss' support (to emulate sizzlingstats)",
	version = PLUGIN_VERSION,
	url = "http://nikkii.us/"
}

public OnPluginStart() {
	RegConsoleCmd("sm_logs", Command_Logs);
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
}

public OnLogUploading(const String:filePath[], const String:title[], const String:map[]) {
	g_sLogUrl[0] = '\0';
}

public OnLogUploaded(const String:filePath[], const String:logUrl[], const String:title[], const String:map[]) {
	// Copy log url to the local url which is hooked with .ss and /log
	strcopy(g_sLogUrl, sizeof(g_sLogUrl), logUrl);
}

public Action:Command_Logs(client, args) {
	OpenLogPanel(client, false);
	return Plugin_Handled;
}

public Action:Command_Say(client, const String:command[], argc) {
	if(argc < 1) {
		return Plugin_Continue;
	}
	decl String:sayText[192];
	GetCmdArgString(sayText, sizeof(sayText));
	
	new startidx = 0;
	if (sayText[strlen(sayText)-1] == '"') {
		sayText[strlen(sayText)-1] = '\0';
		startidx = 1;
	}
	
	if(StrEqual(sayText[startidx], ".ss", false)) {
		OpenLogPanel(client, true);
	}
	return Plugin_Continue;
}

OpenLogPanel(client, bool:isChat = false) {
	if(strlen(g_sLogUrl) == 0) {
		if(isChat) {
			PrintToChat(client, "[SM] No log available.");
		} else {
			ReplyToCommand(client, "[SM] No log available.");
		}
	} else {
		new Handle:kv = CreateKeyValues("motd");

		KvSetNum(kv, "customsvr", 1);
		KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
		KvSetString(kv, "title", "Latest Log");
		KvSetString(kv, "msg", g_sLogUrl);
		
		ShowVGUIPanel(client, "info", kv, true);
	}
}