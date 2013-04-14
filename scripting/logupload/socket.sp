new String:listOfChar[] = "aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789";

UploadLog_Socket(const String:fileName[], const String:fullPath[], const String:title[], const String:map[]) {
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	new Handle:pack = CreateDataPack();
	WritePackString(pack, fileName);
	WritePackString(pack, fullPath);
	WritePackString(pack, title);
	WritePackString(pack, map);
	
	SocketSetArg(socket, pack);
	SocketSetOption(socket, SocketSendBuffer, 1024);
	SocketSetOption(socket, ConcatenateCallbacks, 4096);
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, LOGS_HOST, 80);
}

public OnSocketConnected(Handle:socket, any:pack) {
	// Generate boundary
	new String:genString[26];
	
	for(new i = 1; i <= 26; i++) {
		new randomInt = GetRandomInt(0, 62);
		StrCat(genString, sizeof(genString), listOfChar[randomInt]);
	}
	
	// Put it together with some extra stuff.
	decl String:boundary[54];
	Format(boundary, sizeof(boundary), "---------------------------%s", genString);
	
	// Read the file name from the data pack
	decl String:fileName[64], String:filePath[64], String:title[64], String:map[128];
	ResetPack(pack);
	ReadPackString(pack, fileName, sizeof(fileName));
	ReadPackString(pack, filePath, sizeof(filePath));
	ReadPackString(pack, title, sizeof(title));
	ReadPackString(pack, map, sizeof(map));
	CloseHandle(pack);
	
	// Get the API key
	decl String:apiKey[64];
	Format(apiKey, sizeof(apiKey), "%s", LogUpload_GetKey());
	
	// This part is tricky since we don't want to store it in memory before sending, since sourcemod limits the length of strings heavily
	new boundaryLength = strlen(boundary);
	// Base = 47 + Boundary Length +  2 for \r\n
	new standardLength = 47 + boundaryLength + 2;
	
	new contentLength = 0;
	
	// File property - File Size + 86 + Boundary Length + Name length + File Name length + 2 for \r\n
	contentLength += FileSize(filePath) + 86 + boundaryLength + 7 + strlen(fileName) + 2;
	
	// Request properties (key, map, title)
	contentLength += (standardLength + 3 + strlen(apiKey));
	contentLength += (standardLength + 3 + strlen(map));
	contentLength += (standardLength + 5 + strlen(title));
	
	// End boundary
	contentLength += (boundaryLength + 4 + 2);
	
	// Start the request
	decl String:requestStr[256];
	Format(requestStr, sizeof(requestStr), "POST /upload HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nContent-Type: multipart/form-data; boundary=%s\r\nContent-Length: %i\r\n\r\n", LOGS_HOST, boundary, contentLength);
	SocketSend(socket, requestStr);
	
	// Write the API key
	WriteFormData(socket, boundary, "key", apiKey);
	
	// Write the title
	WriteFormData(socket, boundary, "title", title);
	
	// Write the current map
	WriteFormData(socket, boundary, "map", map);
	
	// Open the file and use the WriteFormFile function
	new Handle:logFile = OpenFile(filePath, "r");
	WriteFormFile(socket, boundary, "logfile", fileName, logFile);
	CloseHandle(logFile);
	
	// Write the final boundary
	Format(requestStr, sizeof(requestStr), "--%s--\r\n", boundary);
	SocketSend(socket, requestStr);
}

WriteFormData(Handle:socket, const String:boundary[], const String:name[], const String:value[]) {
	decl String:dataStr[512];
	Format(dataStr, sizeof(dataStr), "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n", boundary, name);
	SocketSend(socket, dataStr);
	Format(dataStr, sizeof(dataStr), "%s\r\n", value);
	SocketSend(socket, dataStr);
}

WriteFormFile(Handle:socket, const String:boundary[], const String:name[], const String:fileName[], Handle:file) {
	decl String:dataStr[512];
	// Write file header
	Format(dataStr, sizeof(dataStr), "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, name, fileName);
	SocketSend(socket, dataStr);
	
	// Read file into the block
	new readBytes;
	while(!IsEndOfFile(file)) {
		readBytes = ReadFileString(file, dataStr, (sizeof(dataStr) - 1));
		dataStr[readBytes] = '\0';
		SocketSend(socket, dataStr, readBytes);
	}
	
	SocketSend(socket, "\r\n");
}

public OnSocketReceive(Handle:socket, String:receiveData[], const dataSize, any:hFile) {
	// TODO request parsing
}

public OnSocketDisconnected(Handle:socket, any:hFile) {
	CloseHandle(socket);
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:hFile) {
	LogError("socket error %d (errno %d)", errorType, errorNum);
	CloseHandle(socket);
}