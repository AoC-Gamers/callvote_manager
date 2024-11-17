#if defined _callvotemanager_sql_included
	#endinput
#endif
#define _callvotemanager_sql_included

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

ConVar
	g_cvarSQL;

char
	g_sTable[] = "callvote_log";

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

public void OnPluginStart_SQL()
{
	g_cvarSQL = CreateConVar("sm_cvm_sql", "0", "Logging flags <dificulty:1, restartgame:2, kick:4, changemission:8, lobby:16, chapter:32, alltalk:64, ALL:127>", FCVAR_NOTIFY, true, 0.0, true, 127.0);
	RegAdminCmd("sm_cv_sql_install", Command_CreateSQL, ADMFLAG_ROOT, "Install SQL tables");
}

Action Command_CreateSQL(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (!g_cvarSQL.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "SQLDisabled");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	char sQuery[600];
	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
				"CREATE TABLE IF NOT EXISTS `%s` ( \
				`id` INT AUTO_INCREMENT PRIMARY KEY, \
				`authid` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'Client calling for a vote', \
				`created` INT NOT NULL DEFAULT 0 COMMENT 'Creation date in UNIX format', \
				`type` INT NOT NULL DEFAULT 0 COMMENT 'Type of vote', \
				`authidTarget` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'Objective of a kick vote' \
				) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci",
				g_sTable);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
				"CREATE TABLE IF NOT EXISTS `%s` ( \
				`id` INTEGER PRIMARY KEY AUTOINCREMENT, \
				`authid` TEXT NOT NULL DEFAULT '', \
				`created` INTEGER NOT NULL DEFAULT 0, \
				`type` INTEGER NOT NULL DEFAULT 0, \
				`authidTarget` TEXT NOT NULL DEFAULT '' \
				)",
				g_sTable);
		}
		default:
		{
			logEx(false, "[Command_CreateSQL] Unknown SQL driver.");
			return Plugin_Handled;
		}
	}

	if (!SQL_FastQuery(g_db, sQuery))
	{
		logErrorSQL(g_db, sQuery, "Command_CreateSQL");
		CReplyToCommand(iClient, "%t %t", "Tag", "DBQueryError");
		return Plugin_Handled;
	}

	CReplyToCommand(iClient, "%t %t", "Tag", "DBTableCreated");
	logEx(false, "[Command_CreateSQL] Table `%s` created successfully.", g_sTable);
	return Plugin_Handled;
}

public void OnPluginEnd_SQL()
{
	if (!g_cvarSQL.BoolValue)
		return;

	if (g_db == null)
		return;

	delete g_db;
	logEx(true, "[OnPluginEnd] Database connection closed.");
}

void OnConfigsExecuted_SQL()
{
	if (!g_cvarSQL.BoolValue)
		return;

	if (g_db != null)
		return;
	logEx(true, "[OnConfigsExecuted_SQL] Connecting to the database...");
	ConnectDB("callvote", g_sTable);
}

/*****************************************************************
			P L U G I N   F U N C T I O N S
*****************************************************************/

/**
 * Logs a vote action to the SQL database.
 *
 * @param type      The type of vote action (e.g., Kick).
 * @param client    The client ID of the player initiating the vote.
 * @param target    The client ID of the target player (default is 0).
 *
 * This function checks if SQL logging is enabled, if the SQL connection is established,
 * and if the SQL table exists. It then constructs an SQL query to insert the vote action
 * into the database, using either MySQL or SQLite syntax based on the configured SQL driver.
 * If the query execution fails, it logs the error and returns false.
 */
void logSQL(TypeVotes type, int client, int target = 0)
{
	logEx(true, "[logSQL] g_bSQLConnected: %s | g_bSQLTableExists: %s", g_bSQLConnected ? "true" : "false", g_bSQLTableExists ? "true" : "false");
    if (!g_bSQLConnected || !g_bSQLTableExists)
        return;

    char sSteamID_Client[32], sSteamID_Target[32] = "";
    GetClientAuthId(client, AuthId_Engine, sSteamID_Client, sizeof(sSteamID_Client));

    if (type == Kick)
        GetClientAuthId(target, AuthId_Engine, sSteamID_Target, sizeof(sSteamID_Target));

    char sQuery[700];

    switch (g_SQLDriver)
    {
        case SQL_MySQL:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "INSERT INTO `%s` (authid, created, type, authidTarget) VALUES ('%s', UNIX_TIMESTAMP(), %d, '%s')",
                g_sTable, sSteamID_Client, view_as<int>(type), sSteamID_Target);
        }
        case SQL_SQLite:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "INSERT INTO `%s` (authid, created, type, authidTarget) VALUES ('%s', strftime('%%s', 'now'), %d, '%s')",
                g_sTable, sSteamID_Client, view_as<int>(type), sSteamID_Target);
        }
        default:
        {
            logEx(false, "[logSQL] Unknown SQL driver.");
            return;
        }
    }

	logEx(true, "[logSQL] Driver: %s | Query: %s", g_SQLDriver == SQL_MySQL ? "MySQL" : "SQLite", sQuery);
    g_db.Query(CallBack_logSQL, sQuery);
}

public void CallBack_logSQL(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        logEx(false, "[CallBack_logSQL] Error: %s", error);
        return;
    }

	logEx(true, "[CallBack_logSQL] Vote action logged successfully.");
}