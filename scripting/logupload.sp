#pragma semicolon 1

#include <sourcemod>
#include <json>
#include <colors>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <updater>

#undef REQUIRE_EXTENSIONS
#include <cURL>
#include <socket>
#include <smjansson>

#define PLUGIN_VERSION "0.1.5"

#define UPDATE_URL "http://github.nikkii.us/logupload/master/updater.txt"

#define LOGS_HOST "logs.tf"
#define LOGS_PATH "/upload"

#include "logupload/curl.sp"
#include "logupload/socket.sp"

#define CURL_AVAILABLE()		(GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available)
#define SOCKET_AVAILABLE()		(false) //(GetFeatureStatus(FeatureType_Native, "SocketCreate") == FeatureStatus_Available)

// Combine the following values to get the display mode to your liking
// 1: Show log URL in chat
#define DISPLAYFLAG_CHAT (1 << 0)
// 2: Show log URL in a Hint Box
#define DISPLAYFLAG_HINT (1 << 1)
// 4: Show log URL in a center message
#define DISPLAYFLAG_CENTER (1 << 2)

#define MODEFLAG_TOURNAMENT (1 << 0)
#define MODEFLAG_NOBOTS (1 << 1)

new Handle:g_hCvarKey = INVALID_HANDLE;
new Handle:g_hCvarTitle = INVALID_HANDLE;

new Handle:g_hCvarEnabled = INVALID_HANDLE;
new Handle:g_hCvarUploadMode = INVALID_HANDLE;
new Handle:g_hCvarDisplayMode = INVALID_HANDLE;
new Handle:g_hCvarUpdater = INVALID_HANDLE;
new Handle:g_hCvarNextUploadDelay = INVALID_HANDLE;
new Handle:g_hCvarLogDirectory = INVALID_HANDLE;

new Handle:g_hBlueTeamName = INVALID_HANDLE;
new Handle:g_hRedTeamName = INVALID_HANDLE;

new Handle:g_hForwardUploading = INVALID_HANDLE;
new Handle:g_hForwardUploaded = INVALID_HANDLE;
new Handle:g_hCvarTournament = INVALID_HANDLE;

new bool:g_bJansson = false;
new g_iLastUpload = -1;

public Plugin:myinfo = {
	name = "logs.tf uploader",
	author = "Nikki",
	description = "Adds a log auto uploader for Team Fortress rounds",
	version = PLUGIN_VERSION,
	url = "http://nikkii.us"
};

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
	CreateNative("LogUpload_ForceUpload", Native_ForceUpload);
	
	// Register the library
	RegPluginLibrary("logupload");
	
	return APLRes_Success;
}

public OnPluginStart() {
	if (!CURL_AVAILABLE() && !SOCKET_AVAILABLE()) {
		SetFailState("Valid HTTP Extension not found");
	}
	
	// Version cvar
	CreateConVar("sm_logupload_version", PLUGIN_VERSION, "LogUpload version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	// Uploader cvars
	g_hCvarKey = CreateConVar("sm_logupload_key", "", "Your logs.tf API key", FCVAR_PROTECTED);
	g_hCvarTitle = CreateConVar("sm_logupload_title", "{BLUENAME} vs {REDNAME} on {MAP}", "Title to use on logs.tf", FCVAR_PROTECTED);
	
	// Non-protected cvars
	g_hCvarEnabled = CreateConVar("sm_logupload_enabled", "1", "Enables/Disables LogUpload", 0, true, 0.0, true, 1.0);
	g_hCvarUploadMode = CreateConVar("sm_logupload_mode", "1", "Determines when LogUpload should upload logs (0 = End of ANY Game, 1 = End of TOURNAMENT Game)", 0, true, 0.0, true, 3.0);
	g_hCvarDisplayMode = CreateConVar("sm_logupload_display", "3", "Determines how LogUpload displays uploaded log urls\nCombine these values for more than 1:\n1: Show log URL in chat\n2: Show log URL in hint box\n3: Show log URL in center message", 0, true, 0.0, true, 7.0);
	g_hCvarUpdater = CreateConVar("sm_logupload_updater", "1", "Enables/disables Updater", 0, true, 0.0, true, 1.0);
	g_hCvarNextUploadDelay = CreateConVar("sm_logupload_delay", "60", "Sets how long until after a log is uploaded that another one can be.", 0, true);
	
	// Cvars used for titles
	g_hBlueTeamName = FindConVar("mp_tournament_blueteamname");
	g_hRedTeamName = FindConVar("mp_tournament_redteamname");
	
	// Tournament cvar (Only upload logs from tournaments)
	g_hCvarTournament = FindConVar("mp_tournament");
	
	// Log directory cvar (TODO some kind of verificaton on directory?)
	g_hCvarLogDirectory = FindConVar("sv_logsdir");
	
	// Log Name, Title, Map
	g_hForwardUploading = CreateGlobalForward("OnLogUploading", ET_Event, Param_String, Param_String, Param_String);
	// Log URL, Title, Map
	g_hForwardUploaded = CreateGlobalForward("OnLogUploaded", ET_Event, Param_String, Param_String, Param_String, Param_String);
	
	// Win conditions met (maxrounds, timelimit)
	HookEvent("teamplay_game_over", Event_GameOver);

	// Win conditions met (windifference)
	HookEvent("tf_game_over", Event_GameOver);
	
	AutoExecConfig(true, "plugin.logupload");
	
	LoadTranslations("logupload.phrases");
	
	// Set bounds in case we reloaded
	SetConVarBounds(g_hCvarUploadMode, ConVarBound_Upper, true, 3.0);
	SetConVarBounds(g_hCvarDisplayMode, ConVarBound_Upper, true, 5.0);
}

// Updater and SMJansson support

public OnAllPluginsLoaded() {
	if (LibraryExists("updater") && GetConVarBool(g_hCvarUpdater)) {
		Updater_AddPlugin(UPDATE_URL);
	}
	if (LibraryExists("jansson")) {
		g_bJansson = true;
	}
}

public OnLibraryAdded(const String:name[]) {
	if (StrEqual(name, "updater") && GetConVarBool(g_hCvarUpdater)) {
		Updater_AddPlugin(UPDATE_URL);
	}
	if (StrEqual(name, "jansson")) {
		g_bJansson = true;
	}
}

public OnLibraryRemoved(const String:name[]) {
	if (StrEqual(name, "updater") && GetConVarBool(g_hCvarUpdater)) {
		Updater_RemovePlugin();
	}
	if (StrEqual(name, "jansson")) {
		g_bJansson = false;
	}
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
	
	// Parse the title and replace standard things
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
	
	if (StrContains(title, "{BLUESCORE}") != -1) {
		IntToString(GetTeamScore(3), temp, sizeof(temp));
		ReplaceString(title, maxlen, "{BLUESCORE}", temp);
	}
	
	if (StrContains(title, "{REDSCORE}") != -1) {
		IntToString(GetTeamScore(2), temp, sizeof(temp));
		ReplaceString(title, maxlen, "{REDSCORE}", temp);
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
	
	if(numParams > 1) {
		GetNativeString(2, title, sizeof(title));
	}
	if(numParams > 2) {
		GetNativeString(3, map, sizeof(map));
	}
	
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

public Native_ForceUpload(Handle:plugin, numParams) {
	// Required: Nothing.
	ScanLogs();
	return true;
}

// Events

public Event_GameOver(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!GetConVarBool(g_hCvarEnabled)) {
		return;
	}
	new uploadDelay = GetConVarInt(g_hCvarNextUploadDelay);
	if(uploadDelay > 0 && g_iLastUpload != -1 && GetTime() - g_iLastUpload <= uploadDelay) {
		LogError("Last log uploaded %i seconds ago. Skipping search and upload.");
		return;
	}
	if (ShouldLogUpload()) {
		ScanLogs();
		g_iLastUpload = GetTime();
	}
}

// Internal code (Log Scanning, Uploading, Callbacks)

ScanLogs() {
	LogToGame("Log closing for log upload...");
	// Close the current log
	ServerCommand("log on");
	ServerExecute();
	// Execute this next tick
	CreateTimer(0.1, Timer_ScanLogs);
}

public Action:Timer_ScanLogs(Handle:timer) {
	// Scan for logs
	LogMessage("Log scan starting");
	
	decl String:logDirectory[PLATFORM_MAX_PATH], String:fileName[32], String:fullPath[PLATFORM_MAX_PATH];
	
	GetConVarString(g_hCvarLogDirectory, logDirectory, sizeof(logDirectory));
	
	if(!DirExists(logDirectory)) {
		LogError("Unable to find correct log directory, is it set correctly? If it is, please submit a bug report.");
		return Plugin_Handled;
	}
	
	new lowestLogId = -1, currentTime = GetTime();
	decl String:lowestLog[32];
	// Scan for new files, we'll store the most recent files first.
	new Handle:dir = OpenDirectory(logDirectory);
	while(ReadDirEntry(dir, fileName, sizeof(fileName))) {
		if (StrEqual(fileName, ".") || StrEqual(fileName, "..")) {
			continue;
		}
		Format(fullPath, sizeof(fullPath), "%s/%s", logDirectory, fileName);
		new fileTime = GetFileTime(fullPath, FileTime_LastChange);
		if (currentTime - fileTime <= 5) {
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
		LogMessage("Found log %s", lowestLog);
		LogUpload_Upload(lowestLog);
	} else {
		LogError("Unable to find valid log.");
	}
	return Plugin_Handled;
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
	
	LogMessage("Uploading %s (Path: %s)", fileName, fullPath);
	
	if (CURL_AVAILABLE()) {
		UploadLog_cURL(fileName, fullPath, title, map);
	} else {
		LogError("Unable to find valid upload method!");
	}
}

LogUpload_Completed(const String:filePath[], const String:title[], const String:map[], const String:temp[]) {
	if(g_bJansson) {
		// SMJansson is faster and easier to use. Prefer it if we can.
		new Handle:json = json_load(temp);
		if(json_object_get_bool(json, "success")) {
			new logId = json_object_get_int(json, "logId");
			LogUpload_PostProcess(logId, filePath, title, map);
		} else {
			decl String:error[256];
			if(json_object_get_string(json, "error", error, sizeof(error)) != -1) {
				LogMessage("Error while uploading log %s! Error: %s", filePath, error);
			} else {
				LogError("Unknown error while uploading");
			}
		}
		CloseHandle(json);
	} else {
		// However, the include is easier to setup.
		new JSON:json = json_decode(temp);
		if(json != JSON_INVALID) {
			new bool:success = false;
			if (json_get_cell(json, "success", success) && success) {
				new logId = -1;
				if (json_get_cell(json, "log_id", logId)) {
					LogUpload_PostProcess(logId, filePath, title, map);
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
		json_destroy(json);
	}
}

LogUpload_PostProcess(logId, const String:filePath[], const String:title[], const String:map[]) {
	decl String:logUrl[64];
	Format(logUrl, sizeof(logUrl), "http://%s/%i", LOGS_HOST, logId);
	
	LogMessage("Uploaded Log URL: %s", logUrl);
	
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
	
	new mode = GetConVarInt(g_hCvarDisplayMode);
	
	if(mode & DISPLAYFLAG_CHAT) {
		CPrintToChatAll("{green}[LogUpload]{default} %t", "ChatText", logUrl);
	}
	if(mode & DISPLAYFLAG_HINT) {
		PrintHintTextToAll("%t", "HintText", logUrl);
	}
	if(mode & DISPLAYFLAG_CENTER) {
		PrintCenterTextAll("%t", "CenterText", logUrl);
	}
}

bool:ShouldLogUpload() {
	// New mode system, based on multiple conditions which can be checked/added onto the same way as display
	new bool:ret = true;
	new flag = GetConVarInt(g_hCvarUploadMode);
	
	if((flag & MODEFLAG_TOURNAMENT) && ret) {
		// Tournament will be '1' or 'true'
		ret = GetConVarBool(g_hCvarTournament);
	}
	if((flag & MODEFLAG_NOBOTS) && ret) {
		for(new i = 0; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsFakeClient(i) && !IsClientSourceTV(i) && !IsClientReplay(i)) {
				ret = false;
				break;
			}
		}
	}
	return ret;
}