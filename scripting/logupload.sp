#pragma semicolon 1

#include <sourcemod>
#include <json>

#undef REQUIRE_EXTENSIONS
#include <cURL>
#include <socket>
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "0.1.1"

#define LOGS_HOST "logs.tf"
#define LOGS_PATH "/upload"

#include "logupload/curl.sp"

#include "logupload/socket.sp"

#define CURL_AVAILABLE()		(GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available)
#define SOCKET_AVAILABLE()		(false) //(GetFeatureStatus(FeatureType_Native, "SocketCreate") == FeatureStatus_Available)

new Handle:g_hCvarKey = INVALID_HANDLE;
new Handle:g_hCvarTitle = INVALID_HANDLE;
new Handle:g_hCvarUploadMode = INVALID_HANDLE;
new Handle:g_hCvarDisplayMode = INVALID_HANDLE;

new Handle:g_hBlueTeamName = INVALID_HANDLE;
new Handle:g_hRedTeamName = INVALID_HANDLE;

new Handle:g_hForwardUploading = INVALID_HANDLE;
new Handle:g_hForwardUploaded = INVALID_HANDLE;
new Handle:g_hCvarTournament = INVALID_HANDLE;

public Plugin:myinfo = {
	name = "logs.tf uploader",
	author = "Nikki",
	description = "Adds a log auto uploader for Team Fortress rounds",
	version = PLUGIN_VERSION,
	url = "http://nikkii.us"
};

public OnPluginStart() {
	if (!CURL_AVAILABLE() && !SOCKET_AVAILABLE()) {
		SetFailState("Valid HTTP Extension not found");
	}
	
	// Version cvar
	CreateConVar("sm_logupload_version", PLUGIN_VERSION, "LogUpload version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	// Uploader cvars
	g_hCvarKey = CreateConVar("sm_logupload_key", "", "Your logs.tf API key", FCVAR_PROTECTED);
	g_hCvarTitle = CreateConVar("sm_logupload_title", "Auto Uploaded Log", "Title to use on logs.tf", FCVAR_PROTECTED);
	
	// Non-protected cvars
	g_hCvarUploadMode = CreateConVar("sm_logupload_mode", "0", "Determines when LogUpload should upload logs (0 = End of ANY Game, 1 = End of TOURNAMENT Game)", 0, true, 0.0, true, 1.0);
	g_hCvarDisplayMode = CreateConVar("sm_logupload_display", "0", "Determines how LogUpload displays uploaded log urls (0 = Chat, 1 = Hint, 2 = Center Text)", 0, true, 0.0, true, 2.0);
	
	// Cvars used for titles
	g_hBlueTeamName = FindConVar("mp_tournament_blueteamname");
	g_hRedTeamName = FindConVar("mp_tournament_redteamname");
	
	// Tournament cvar (Only upload logs from tournaments)
	g_hCvarTournament = FindConVar("mp_tournament");
	
	// Log Name, Title, Map
	g_hForwardUploading = CreateGlobalForward("OnLogUploading", ET_Event, Param_String, Param_String, Param_String);
	// Log URL, Title, Map
	g_hForwardUploaded = CreateGlobalForward("OnLogUploaded", ET_Event, Param_String, Param_String, Param_String);
	
	// Win conditions met (maxrounds, timelimit)
	HookEvent("teamplay_game_over", Event_GameOver);

	// Win conditions met (windifference)
	HookEvent("tf_game_over", Event_GameOver);
	
	AutoExecConfig(true, "plugin.logupload");
	
	LoadTranslations("logupload.phrases");
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	// cURL
	
	MarkNativeAsOptional("curl_easy_init");
	MarkNativeAsOptional("curl_easy_setopt_int_array");
	MarkNativeAsOptional("curl_easy_setopt_handle");
	MarkNativeAsOptional("curl_easy_setopt_string");
	MarkNativeAsOptional("curl_easy_perform_thread");
	MarkNativeAsOptional("curl_formadd");
	MarkNativeAsOptional("curl_httppost");
	
	// Socket
	
	MarkNativeAsOptional("SocketCreate");
	MarkNativeAsOptional("SocketSetArg");
	MarkNativeAsOptional("SocketSetOption");
	MarkNativeAsOptional("SocketConnect");
	MarkNativeAsOptional("SocketSend");
	
	// Natives
	
	CreateNative("LogUpload_UploadLog", Native_UploadLog);
	
	return APLRes_Success;
}

// 'getters' for cvars
String:LogUpload_GetKey() {
	// Read the API key cvar
	decl String:apiKey[64];
	GetConVarString(g_hCvarKey, apiKey, sizeof(apiKey));
	return apiKey;
}

String:LogUpload_GetLogTitle() {
	// Read the title cvar, max length is 40 on logs.tf, so give a little extra for replacements
	decl String:title[256];
	GetConVarString(g_hCvarTitle, title, sizeof(title));
	
	ParseLogTitle(title, sizeof(title));
	
	return title;
}

String:LogUpload_GetURL() {
	decl String:url[128];
	Format(url, sizeof(url), "http://%s/%s", LOGS_HOST, LOGS_PATH);
	return url;
}

// Misc parsing

ParseLogTitle(String:title[], maxlen) {
	// Very simple replacements, a good base would be "{BLUENAME} vs {REDNAME} - {MAP}"
	decl String:temp[64];
	
	if (StrContains(title, "{MAP}") != -1) {
		GetCurrentMap(temp, sizeof(temp));
		ReplaceString(title, maxlen, "{MAP}", temp);
	}
	
	if (StrContains(title, "{BLUENAME}") != -1) {
		GetConVarString(g_hBlueTeamName, temp, sizeof(temp));
		ReplaceString(title, maxlen, "{BLUENAME}", temp);
	}
	
	if (StrContains(title, "{REDNAME}") != -1) {
		GetConVarString(g_hRedTeamName, temp, sizeof(temp));
		ReplaceString(title, maxlen, "{REDNAME}", temp);
	}
}

// Natives

public Native_UploadLog(Handle:plugin, numParams) {
	// Required: String (Log File), Optional: String (Log Title), String (Map Name)
	if(numParams < 1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid number of params");
	}
	
	decl String:filePath[PLATFORM_MAX_PATH], String:title[256], String:map[128];
	GetNativeString(1, filePath, sizeof(filePath));
	GetNativeString(2, title, sizeof(title));
	GetNativeString(3, map, sizeof(map));
	
	if(strlen(title) > 0) {
		ParseLogTitle(title, sizeof(title));
	} else {
		strcopy(title, sizeof(title), LogUpload_GetLogTitle());
	}
	
	if(strlen(map) == 0) {
		GetCurrentMap(map, sizeof(map));
	}
	
	// TODO callback?
	LogUpload_DoUpload(filePath, title, map);
	
	return true;
}

// Events

public Event_GameOver(Handle:event, const String:name[], bool:dontBroadcast) {
	new uploadMode = GetConVarInt(g_hCvarUploadMode);
	new bool:tournament = GetConVarBool(g_hCvarTournament);
	if (uploadMode == 0 || uploadMode == 1 && tournament) {
		ScanLogs();
	}
}

// Internal code (Log Scanning, Uploading, Callbacks)

ScanLogs() {
	LogToGame("Log closing...");
	// Close the current log
	ServerCommand("log on");
	ServerExecute();
	// Execute this next tick
	CreateTimer(0.1, Timer_ScanLogs);
}

public Action:Timer_ScanLogs(Handle:timer) {
	// Scan for logs
	decl String:fileName[32], String:fullPath[PLATFORM_MAX_PATH];
	PrintToServer("Log scan starting");
	
	new lowestLogId = -1;
	decl String:lowestLog[32];
	// Scan for new files, we'll store the most recent files first.
	new Handle:dir = OpenDirectory("logs/");
	while(ReadDirEntry(dir, fileName, sizeof(fileName))) {
		if (StrEqual(fileName, ".")) {
			continue;
		}
		Format(fullPath, sizeof(fullPath), "logs/%s", fileName);
		new fileTime = GetFileTime(fullPath, FileTime_LastChange);
		if (GetTime() - fileTime <= 5) {
			decl String:logIdS[4];
			strcopy(logIdS, sizeof(logIdS), fileName[5]);
			new logId = StringToInt(logIdS);
			if(lowestLogId == -1 || logId < lowestLogId) {
				lowestLogId = logId;
				Format(lowestLog, sizeof(lowestLog), "%s", fullPath);
			}
		}
	}
	CloseHandle(dir);
	// This is the log we closed
	if(lowestLogId != -1) {
		PrintToServer("Found log %s", lowestLog);
		LogUpload_Upload(fullPath);
	} else {
		PrintToServer("Unable to find valid log.");
	}
}

LogUpload_Upload(const String:fullPath[]) {	
	decl String:title[41], String:map[64];
	strcopy(title, sizeof(title), LogUpload_GetLogTitle());
	GetCurrentMap(map, sizeof(map));
	
	LogUpload_DoUpload(fullPath, title, map);
}

LogUpload_DoUpload(const String:fullPath[], const String:title[], const String:map[]) {
	Call_StartForward(g_hForwardUploading);
	
	Call_PushString(fullPath);
	Call_PushString(title);
	Call_PushString(map);
	
	new Action:result;
	Call_Finish(_:result);
	
	if(result == Plugin_Stop) {
		return;
	}
	
	decl String:fileName[PLATFORM_MAX_PATH];
	
	new lastIdx = FindCharInString(fullPath, '/', true);
	if(lastIdx > 0) {
		strcopy(fileName, sizeof(fileName), fullPath[lastIdx + 1]);
	} else {
		strcopy(fileName, sizeof(fileName), fullPath);
	}
	
	if (CURL_AVAILABLE()) {
		UploadLog_cURL(fileName, fullPath, title, map);
	} else if (SOCKET_AVAILABLE()) {
		UploadLog_Socket(fileName, fullPath, title, map);
	} else {
		LogError("Unable to find valid upload method!");
	}
}

LogUpload_Completed(const String:filePath[], const String:title[], const String:map[], JSON:json) {
	new bool:success = false;
	if (json_get_cell(json, "success", success) && success) {
		new logId = -1;
		if (json_get_cell(json, "log_id", logId)) {
			decl String:logUrl[64];
			Format(logUrl, sizeof(logUrl), "http://%s/%i", LOGS_HOST, logId);
			
			PrintToServer("Uploaded Log URL: %s", logUrl);
			
			new Action:result;
			Call_StartForward(g_hForwardUploaded);
			
			Call_PushString(filePath);
			Call_PushString(logUrl);
			Call_PushString(title);
			Call_PushString(map);
			
			Call_Finish(_:result);
			
			if(result == Plugin_Stop) {
				return;
			}
			
			switch(GetConVarInt(g_hCvarDisplayMode)) {
				case 0: {
					PrintToChatAll("%T", "ChatText", logUrl);
				}
				case 1: {
					PrintHintTextToAll("%T", "HintText", logUrl);
				}
				case 2: {
					PrintCenterTextAll("%T", "CenterText", logUrl);
				}
			}
		}
	} else {
		decl String:error[256];
		if (json_get_string(json, "error", error, sizeof(error))) {
			LogError("Error while uploading log %s! Error: %s", filePath, error);
		} else {
			LogError("Unknown error while uploading");
		}
	}
}