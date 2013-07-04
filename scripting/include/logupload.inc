#if defined _logupload_included_
  #endinput
#endif
#define _logupload_included_

/**
 * Called when a log file is being uploaded
 *
 * @param filePath	The path of the log uploading
 * @param title		The title of the log being uploaded
 * @param map		The map of the log being uploaded
 * @return Action	Plugin_Stop to stop upload
 */
forward OnLogUploading(const String:filePath[], const String:title[], const String:map[]);

/**
 * Called when a log file is done uploading
 *
 * @param filePath	The path of the log uploading
 * @param logUrl	The uploaded log URL
 * @param title		The title of the log being uploaded
 * @param map		The map of the log being uploaded
 * @return Action	Plugin_Stop to stop broadcast of log url
 */
forward OnLogUploaded(const String:filePath[], const String:logUrl[], const String:title[], const String:map[]);

/**
 * Uploads a log file using the options specified in the config
 *
 * @param filePath	The path of the log to upload
 * @param title		The title to give the log, it can be the same format as the cvar, or empty to generate one.
 * @param map		The map to specify for the log, it can be empty to get the current map.
 * @return true if file is uploading, false if failed.
 */
native LogUpload_UploadLog(const String:filePath[], const String:title[], const String:map[]);

/**
 * Uploads a log file using the built in search function
 */
native LogUpload_ForceUpload();

public SharedPlugin:__pl_logupload = 
{
	name = "logupload",
	file = "logupload.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

public __pl_logupload_SetNTVOptional()
{
	MarkNativeAsOptional("LogUpload_UploadLog");
}