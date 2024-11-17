#if defined _callvotekicklimit_sql_included
	#endinput
#endif
#define _callvotekicklimit_sql_included

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

ConVar
	g_cvarSQL;

char 
	g_sTable[] = "callvote_kicklimit";

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/
public void OnPluginStart_SQL()
{
	g_cvarSQL = CreateConVar("sm_cvkl_sql", "0", "Enables kick counter registration to the database, if disabled it uses local memory.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	RegAdminCmd("sm_cvkl_sql_install", Command_CreateSQL, ADMFLAG_ROOT, "Install SQL tables");
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
                `authidTarget` TEXT NOT NULL DEFAULT '' \
                )",
                g_sTable);
        }
        default:
        {
            log(false, "[Command_CreateSQL] Unknown SQL driver.");
            CReplyToCommand(iClient, "%t %t", "Tag", "UnknownSQLDriver");
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
    log(false, "[Command_CreateSQL] Table `%s` created successfully.", g_sTable);
    return Plugin_Handled;
}

void OnConfigsExecuted_SQL()
{
	if (!g_cvarSQL.BoolValue)
		return;

	if (g_db != null)
		return;

	ConnectDB("callvote", g_sTable);
}

/*****************************************************************
			P L U G I N   F U N C T I O N S
*****************************************************************/

/**
 * Inserts a record into the database based on the current SQL driver.
 *
 * @param sClientID The authid of the client initiating the vote.
 * @param sTargetID The authid of the target player being voted to be kicked.
 */
void sqlinsert(const char[] sClientID, const char[] sTargetID)
{
    if (!g_cvarSQL.BoolValue || !g_bSQLConnected || !g_bSQLTableExists)
        return;

    char sQuery[600];

    switch (g_SQLDriver)
    {
        case SQL_MySQL:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "INSERT INTO `%s` (`authid`, `created`, `authidTarget`) VALUES ('%s', UNIX_TIMESTAMP(), '%s')",
                g_sTable, sClientID, sTargetID);
        }
        case SQL_SQLite:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "INSERT INTO `%s` (`authid`, `created`, `authidTarget`) VALUES ('%s', strftime('%%s', 'now'), '%s')",
                g_sTable, sClientID, sTargetID);
        }
        default:
        {
            log(false, "[sqlinsert] Unknown SQL driver.");
            return;
        }
    }

    log(true, "[sqlinsert] Driver: %s | Query: %s", g_SQLDriver == SQL_MySQL ? "MySQL" : "SQLite", sQuery);
	DataPack dp;
   	g_db.Query(CallBack_SQLInsert, sQuery, dp);
	dp.WriteString(sQuery);
}

public void CallBack_SQLInsert(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);

    if (results == null)
    {
		char
			sQuery[600];

       	dp.Reset();
        dp.ReadString(sQuery, sizeof(sQuery));
		
        log(false, "[CallBack_SQLInsert] SQL failed: %s", error);
		log(false, "[CallBack_SQLInsert] Query dump: %s", sQuery);
        return;
    }

	delete dp;
}

/**
 * Retrieves the count of kick votes for a specific client within the last 24 hours.
 *
 * @param iClient The client index.
 * @param sSteamID The SteamID of the client.
 */
void GetCountKick(int iClient, const char[] sSteamID)
{
    char sQuery[255];

    switch (g_SQLDriver)
    {
        case SQL_MySQL:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "SELECT COUNT(*) FROM `%s` WHERE created >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 DAY)) AND authid = '%s'",
                g_sTable, sSteamID);
        }
        case SQL_SQLite:
        {
            g_db.Format(sQuery, sizeof(sQuery),
                "SELECT COUNT(*) FROM `%s` WHERE created >= strftime('%%s', 'now', '-1 day') AND authid = '%s'",
                g_sTable, sSteamID);
        }
        default:
        {
            log(false, "[GetCountKick] Unknown SQL driver.");
            return;
        }
    }

    log(true, "[GetCountKick] Driver: %s | Query: %s", g_SQLDriver == SQL_MySQL ? "MySQL" : "SQLite", sQuery);
    g_db.Query(CallBack_GetCountKick, sQuery, GetClientUserId(iClient));
}

/**
 * Callback function for retrieving the count of kick votes from the database.
 *
 * @param db The database connection.
 * @param results The result set containing the count of kicks.
 * @param error The error message, if any.
 * @param data The user ID associated with the client.
 */
public void CallBack_GetCountKick(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        log(false, "[CallBack_GetCountKick] Error: %s", error);
        return;
    }

    int iClient = GetClientOfUserId(data);
    if (iClient == CONSOLE)
        return;

    int iKick = 0;

    if (results.FetchRow())
    {
        iKick = results.FetchInt(0);
    }

    log(true, "[CallBack_GetCountKick] Client: %N | Kicks: %d", iClient, iKick);
    if (iKick)
    {
        g_Players[iClient].Kick = iKick;
        GetClientAuthId(iClient, AuthId_Steam2, g_Players[iClient].ClientID, MAX_AUTHID_LENGTH);
    }
    else
        IsNewClient(iClient);
}