/*
	callvote_stocks.inc
	Copyright (C) 2023 Lechuga

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#if defined _callvote_stocks_included
	#endinput
#endif
#define _callvote_stocks_included

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

#define CONSOLE				  0
#define DIR_CALLVOTE		  "logs/callvote.log"
#define MAX_REASON_LENGTH	  512

/**
 * @section Bitwise values definitions for type vote.
 */
#define VOTE_CHANGEDIFFICULTY (1 << 0)	  // 1
#define VOTE_RESTARTGAME	  (1 << 1)	  // 2
#define VOTE_KICK			  (1 << 2)	  // 4
#define VOTE_CHANGEMISSION	  (1 << 3)	  // 8
#define VOTE_RETURNTOLOBBY	  (1 << 4)	  // 16
#define VOTE_CHANGECHAPTER	  (1 << 5)	  // 32
#define VOTE_CHANGEALLTALK	  (1 << 6)	  // 64

stock char
	g_sLogPath[PLATFORM_MAX_PATH];

stock ConVar
	g_cvarLog,
	g_cvarEnable,
	g_cvarDebug;

enum TypeVotes
{
	ChangeDifficulty = 0,
	RestartGame		 = 1,
	Kick			 = 2,
	ChangeMission	 = 3,
	ReturnToLobby	 = 4,
	ChangeChapter	 = 5,
	ChangeAllTalk	 = 6,

	TypeVotes_Size	 = 7
};

bool
	g_bSQLConnected,
	g_bSQLTableExists;

enum SQLDriver
{
	SQL_MySQL  = 0,
	SQL_SQLite = 1,
}

Database
	g_db;

SQLDriver
	g_SQLDriver;

/**
 * Check if the translation file exists
 *
 * @param translation	Translation name.
 * @noreturn
 */
stock void LoadTranslation(const char[] translation)
{
	char
		sPath[PLATFORM_MAX_PATH],
		sName[64];

	Format(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}

/*
 * @brief: Print debug message to log file
 * @param: sMessage - Message to print
 * @param: any - Arguments
 */
stock void log(bool onlydebug, const char[] sMessage, any...)
{
	if (!g_cvarLog.BoolValue)
		return;

	static int check = -1;
	static char
		sFilename[64],
		sFormat[1024];
	
	VFormat(sFormat, sizeof(sFormat), sMessage, 3);
	File file = OpenFile(g_sLogPath, "a+");

	GetPluginFilename(null, sFilename, sizeof(sFilename));
	if ((check = FindCharInString(sFilename, '/', true)) != -1 || (check = FindCharInString(sFilename, '\\', true)) != -1)
		Format(sFilename, sizeof(sFilename), "%s", sFilename[check + 1]);

	ReplaceString(sFilename, sizeof(sFilename), ".smx", "", false);
	ReplaceString(sFilename, sizeof(sFilename), "callvote_", "", false);

	if (g_cvarDebug.BoolValue && onlydebug)
		LogToFileEx(g_sLogPath, "[Debug] [%s] %s", sFilename, sFormat);
	else if (!onlydebug)
		LogToFileEx(g_sLogPath, "[%s] %s", sFilename, sFormat);

	delete file;
}

/**
 * Connects to the database using the specified configuration name.
 *
 * @param sConfigName The name of the database configuration to use for the connection.
 *
 * This function checks if the specified database configuration exists. If it does not,
 * it logs an error message and sets the global variable `g_bSQLConnected` to false.
 * If the configuration exists, it attempts to connect to the database using the provided
 * configuration name and calls the `ConnectCallback` function upon completion.
 */
stock void ConnectDB(char[] sConfigName, char[] sTable = "")
{
	if (!SQL_CheckConfig(sConfigName))
	{
		log(false, "[ConnectDB] Database failure: could not find database config: %s", sConfigName);
		g_bSQLConnected = false;
	}

	log(true, "[ConnectDB] Data: %s", (sTable[0] == '\0') ? "No additional data" : sTable);

	if (sTable[0] == '\0')
		Database.Connect(ConnectCallback, sConfigName);
	else
	{
		DataPack dp = new DataPack();
		dp.WriteString(sTable);

		Database.Connect(ConnectCallback, sConfigName, dp);
	}

}

/**
 * Callback function for handling database connection.
 *
 * @param database  The database connection object.
 * @param error     The error message if the connection failed.
 * @param data      Additional data passed to the callback.
 *
 * This function is called when a connection to the database is attempted.
 * It logs the success or failure of the connection, sets the database charset to UTF-8,
 * and determines the SQL driver being used. It also checks if table exists.
 */
stock void ConnectCallback(Database database, const char[] error, any data)
{
	if(database == null)
	{
		log(false, "[ConnectCallback] Could not connect to database: %s", error);
		g_bSQLConnected = false;
	}
	if (error[0] != '\0')
	{
		log(false, "[ConnectCallback] Error to connect to database: %s", error);
		g_bSQLConnected = false;
		return;
	}
	else
		g_bSQLConnected = true;

	log(true, "[ConnectCallback] Successfully connected to database.");

	char
		sSQLDriverName[64];

	g_db = database;
	database.Driver.GetIdentifier(sSQLDriverName, sizeof(sSQLDriverName));
	log(true, "[ConnectCallback] Driver: %s", sSQLDriverName);

	if (StrEqual(sSQLDriverName, "mysql", true))
	{
		g_SQLDriver = SQL_MySQL;
		if (database.SetCharset("utf8"))
			log(true, "[ConnectCallback] Database charset set to UTF-8.");
		else
			log(true, "[ConnectCallback] Failed to set database charset.");
	}
	else if (StrEqual(sSQLDriverName, "sqlite", true))
		g_SQLDriver = SQL_SQLite;

	if (data == 0)
	{
		log(true, "[ConnectCallback] No additional data provided.");
		return;
	}

	char
		sTable[64];

	DataPack
		dp = view_as<DataPack>(data);

	dp.Reset();
	dp.ReadString(sTable, sizeof(sTable));
	delete dp;
	g_bSQLTableExists = isTableExists(sTable);

	if (g_bSQLTableExists)
		log(true, "[ConnectCallback] Table %s exists.", sTable);
	else
		log(true, "[ConnectCallback] Table %s does not exist.", sTable);
}

/**
 * Checks if a table exists in the database.
 *
 * @param sTable        The name of the table to check.
 * @return              True if the table exists, false otherwise.
 */
stock bool isTableExists(const char[] sTable)
{
	char
		sQuery[255],
		sError[255];

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery), "SELECT 1 FROM `%s` LIMIT 1", sTable);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery), "SELECT name FROM sqlite_master WHERE type='table' AND name='%s'", sTable);
		}
		default:
		{
			log(false, "[isTableExists] Unknown SQL driver.");
			return false;
		}
	}

	DBResultSet QueryTableExists = SQL_Query(g_db, sQuery);
	if (QueryTableExists == null)
	{
		SQL_GetError(g_db, sError, sizeof(sError));
		log(false, "[isTableExists] Query failed for table '%s': %s", sTable, sError);
		return false;
	}

	bool exists = QueryTableExists.FetchRow();
	delete QueryTableExists;

	return exists;
}

/**
 * Logs SQL errors and the corresponding query that caused the error.
 *
 * @param db        The database connection handle.
 * @param sQuery    The SQL query that failed.
 * @param sName     The name of the source or context where the error occurred.
 */
stock logErrorSQL(Database db, const char[] sQuery, const char[] sName)
{
	char sSQLError[250];
	SQL_GetError(db, sSQLError, sizeof(sSQLError));
	log(false, "[%s] SQL failed: %s", sName, sSQLError);
	log(false, "[%s] Query dump: %s", sName, sQuery);
}

/*****************************************************************
			L 4 D H O O K S
*****************************************************************/

#if !defined _l4d_stocks_included

enum L4DTeam
{
	L4DTeam_Unassigned				= 0,
	L4DTeam_Spectator				= 1,
	L4DTeam_Survivor				= 2,
	L4DTeam_Infected				= 3
}

/**
 * Returns the clients team using L4DTeam.
 *
 * @param client		Player's index.
 * @return				Current L4DTeam of player.
 * @error				Invalid client index.
 */
stock L4DTeam L4D_GetClientTeam(int client)
{
	int team = GetClientTeam(client);
	return view_as<L4DTeam>(team);
}

/**
 * Returns a valid client indexed.
 *
 * @param client		Player's index.
 * @return				true if the client is valid, false if not.
 */
stock bool IsValidClient(int iClient)
{
	return (IsValidClientIndex(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient));
}

/**
 * Client indexed.
 *
 * @param client		Player's index.
 * @return				true if the client is valid, false if not.
 */
stock bool IsValidClientIndex(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients);
}

#endif

