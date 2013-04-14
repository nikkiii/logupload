new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_VERBOSE,0}
};

#define LOGUPLOAD_TEMPPATH "logupload_temp.txt"

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

UploadLog_cURL(const String:fileName[], const String:fullPath[], const String:title[], const String:map[]) {
	new Handle:cURL = curl_easy_init();
	if (cURL != INVALID_HANDLE) {
		new Handle:form = curl_httppost();
		curl_formadd(form, CURLFORM_COPYNAME, "key", CURLFORM_COPYCONTENTS, LogUpload_GetKey(), CURLFORM_END);
		curl_formadd(form, CURLFORM_COPYNAME, "title", CURLFORM_COPYCONTENTS, title, CURLFORM_END);
		curl_formadd(form, CURLFORM_COPYNAME, "map", CURLFORM_COPYCONTENTS, map, CURLFORM_END);
		curl_formadd(form, CURLFORM_COPYNAME, "logfile", CURLFORM_FILE, fullPath, CURLFORM_END);
		
		CURL_DEFAULT_OPT(cURL);
		curl_easy_setopt_handle(cURL, CURLOPT_HTTPPOST, form);
		
		new Handle:file = curl_OpenFile(LOGUPLOAD_TEMPPATH, "w");
		
		curl_easy_setopt_handle(cURL, CURLOPT_WRITEDATA, file);
		curl_easy_setopt_string(cURL, CURLOPT_URL, LogUpload_GetURL());
		
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, _:file);
		WritePackString(pack, fullPath);
		WritePackString(pack, title);
		WritePackString(pack, map);
		WritePackCell(pack, _:form);
		
		curl_easy_perform_thread(cURL, cURL_OnComplete, pack);
	} else {
		LogError("Unable to upload %s, curl_easy_init failed", fileName);
	}
}

public cURL_OnComplete(Handle:handle, CURLcode:code, any:pack) {
	ResetPack(pack);
	// Close cURL's file
	CloseHandle(Handle:ReadPackCell(pack));
	
	decl String:filePath[PLATFORM_MAX_PATH], String:title[64], String:map[128];
	if (code == CURLE_OK) {
		decl String:temp[512]; // Data usually won't be longer than this.
		new Handle:file = OpenFile(LOGUPLOAD_TEMPPATH, "r");
		ReadFileString(file, temp, sizeof(temp));
		CloseHandle(file);
		
		ReadPackString(pack, filePath, sizeof(filePath));
		ReadPackString(pack, title, sizeof(title));
		ReadPackString(pack, map, sizeof(map));
		
		new JSON:json = json_decode(temp);
		if(json != JSON_INVALID) {
			LogUpload_Completed(filePath, title, map, json);
		}
		json_destroy(json);
	}
	DeleteFile(LOGUPLOAD_TEMPPATH);
	
	// Close the cURL handles
	CloseHandle(handle);
	CloseHandle(Handle:ReadPackCell(pack));
	
	// Close the pack
	CloseHandle(pack);
}