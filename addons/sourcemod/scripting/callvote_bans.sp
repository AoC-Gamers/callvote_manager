#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>

#undef REQUIRE_PLUGIN
#include <callvotemanager>
#define REQUIRE_PLUGIN

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

#define PLUGIN_VERSION "1.1.0"

/**
 * Player profile.
 *
 */
enum struct PlayerBans
{
	char steamid2[MAX_AUTHID_LENGTH];	 // Player SteamID 64
	int	 created;						 // Ban creation date
	int	 type;							 // Ban type
}

PlayerBans
	g_PlayersBans[MAXPLAYERS + 1];

bool
	g_bshowCooldown;

char
	g_sTable[] = "callvote_bans";

/*****************************************************************
			P L U G I N   I N F O
*****************************************************************/
public Plugin myinfo =
{
	name		= "Call Vote Bans",
	author		= "lechuga",
	description = "Sanctions with the blocking of calls to votes",
	version		= PLUGIN_VERSION,
	url			= "https://github.com/lechuga16/callvote_manager"
}

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

public void OnPluginStart()
{
	LoadTranslation("callvote_bans.phrases");
	LoadTranslation("common.phrases");
	g_cvarDebug	 = CreateConVar("sm_cvb_debug", "0", "Debug sMessagess", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarEnable = CreateConVar("sm_cvb_enable", "1", "Enable plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarLog	 = CreateConVar("sm_cvb_log", "1", "Log sMessages", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegAdminCmd("sm_cvb_sql_install", Command_CreateSQL, ADMFLAG_ROOT, "Install SQL tables");
	RegAdminCmd("sm_cvb_show", Command_ShowBans, ADMFLAG_GENERIC, "Show bans");
	RegConsoleCmd("sm_cvb_status", Command_Status, "Shows if I'm banned");
	RegAdminCmd("sm_cvb_ban", Command_Ban, ADMFLAG_BAN, "Show bans");
	RegAdminCmd("sm_cvb_unban", Command_UnBan, ADMFLAG_BAN, "Show bans");

	AutoExecConfig(false, "callvote_bans");
	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), DIR_CALLVOTE);
}

Action Command_CreateSQL(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	char sQuery[500];

	switch (g_SQLDriver)
	{
		case (SQL_MySQL):
		{
			g_db.Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` ( `id` int(6) NOT NULL auto_increment, `authid` varchar(64) character set utf8 NOT NULL default '', `type` int(6) NOT NULL default '0', `admin` varchar(64) character set utf8 NOT NULL default '', PRIMARY KEY(`id`)) ENGINE = InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci", g_sTable);
		}
		case (SQL_SQLite):
		{
			g_db.Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` ( `id` INTEGER PRIMARY KEY AUTOINCREMENT, `authid` TEXT NOT NULL DEFAULT '', `type` INTEGER NOT NULL DEFAULT 0, `admin` TEXT NOT NULL DEFAULT '')", g_sTable);
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

Action Command_Status(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (iArgs != 0)
	{
		CReplyToCommand(iClient, "%t %t: sm_cvb_status", "Tag", "Usage");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	if (!g_bSQLTableExists)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBTableNotExists");
		return Plugin_Handled;
	}

	if (g_PlayersBans[iClient].type == 0)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "ShowNoBan");
		return Plugin_Handled;
	}

	char sName[32];
	GetClientName(iClient, sName, sizeof(sName));
	VotesMessage(iClient, g_PlayersBans[iClient].type, sName);

	return Plugin_Handled;
}

Action Command_ShowBans(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (iArgs != 1)
	{
		CReplyToCommand(iClient, "%t %t: sm_cvb_show <#userid|name|steamid>", "Tag", "Usage");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	if (!g_bSQLTableExists)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBTableNotExists");
		return Plugin_Handled;
	}

	char sBuffer[100];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));

	// use steamid to offlineban
	bool bIsOffline = ((StrContains(sBuffer, "STEAM_1", false) != -1) || (StrContains(sBuffer, "STEAM_0", false) != -1));
	int	 iTarget	= PlayerInGame(sBuffer);

	if (bIsOffline && iTarget == -1)
	{
		if (!g_bshowCooldown)
		{
			g_bshowCooldown = true;
			CreateTimer(3.0, Timer_ShowBans, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			CReplyToCommand(iClient, "%t %t", "Tag", "Cooldown");
			return Plugin_Handled;
		}

		ReplaceString(sBuffer, sizeof(sBuffer), "STEAM_0", "STEAM_1", false);

		int iTypeBan = g_PlayersBans[iClient].type;
		if (iTypeBan == 0)
			CReplyToCommand(iClient, "%t %t", "Tag", "ShowNoBan");
		else
			VotesMessage(iClient, iTypeBan, sBuffer);
		return Plugin_Handled;
	}
	else if (iTarget == -1)
		iTarget = FindTarget(iClient, sBuffer, true);

	if (iTarget == -1)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PlayerNotFound");
		return Plugin_Handled;
	}

	if (g_PlayersBans[iTarget].type == 0)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "ShowNoBan");
		return Plugin_Handled;
	}

	char sName[32];
	GetClientName(iTarget, sName, sizeof(sName));
	VotesMessage(iClient, g_PlayersBans[iTarget].type, sName);

	return Plugin_Handled;
}

Action Timer_ShowBans(Handle hTimer)
{
	g_bshowCooldown = false;
	return Plugin_Stop;
}

Action Command_Ban(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (iArgs < 2)
	{
		CReplyToCommand(iClient, "%t %t: sm_cvb_ban <#userid|name|steamid> <TypeBans>", "Tag", "Usage");
		CReplyToCommand(iClient, "%t %t", "Tag", "SeeTypeBans");
		PrintToConsole(iClient, "%t", "TypeBans");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	if (!g_bSQLTableExists)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBTableNotExists");
		return Plugin_Handled;
	}

	char sBuffer[100];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));
	if (!IsValidInput(sBuffer))
	{
		log(false, "[Command_Ban] Invalid input detected: %s", sBuffer);
		CReplyToCommand(iClient, "%t %t", "Tag", "InvalidInput");
		return Plugin_Handled;
	}

	int iType = GetCmdArgInt(2);

	if (!IsVoteTypeValid(iType))
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "SeeTypeBans");
		PrintToConsole(iClient, "%t", "TypeBans");
		return Plugin_Handled;
	}

	// use steamid to offlineban
	bool bIsOffline = ((StrContains(sBuffer, "STEAM_1", false) != -1) || (StrContains(sBuffer, "STEAM_0", false) != -1));
	int	 iTarget	= PlayerInGame(sBuffer);

	if (bIsOffline && iTarget == -1)
	{
		ReplaceString(sBuffer, sizeof(sBuffer), "STEAM_0", "STEAM_1", false);
		int iBans = GetBans(0, sBuffer, true);

		switch (iBans)
		{
			case -1: CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
			case 0:
			{
				if (CreateBan(iClient, 0, iType, sBuffer, true))
					CReplyToCommand(iClient, "%t %t", "Tag", "BanCreated");
				else
					CReplyToCommand(iClient, "%t %t", "Tag", "BanNotCreated");
			}
			default:
			{
				if (iBans > 0)
				{
					if (UpdateBan(iClient, 0, iType, sBuffer, true))
						CReplyToCommand(iClient, "%t %t", "Tag", "BanUpdated");
					else
						CReplyToCommand(iClient, "%t %t", "Tag", "BanNotCreated");
				}
			}
		}

		return Plugin_Handled;
	}
	else if (iTarget == -1)
		iTarget = FindTarget(iClient, sBuffer, true);

	if (iTarget == -1)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PlayerNotFound");
		return Plugin_Handled;
	}

	// use target to onlineban
	if (g_PlayersBans[iTarget].type == 0)
	{
		if (CreateBan(iClient, iTarget, iType))
			CReplyToCommand(iClient, "%t %t", "Tag", "BanCreated");
		else
			CReplyToCommand(iClient, "%t %t", "Tag", "BanNotCreated");
	}
	else
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PlayerAlreadyBanned");

		if (UpdateBan(iClient, iTarget, iType))
			CReplyToCommand(iClient, "%t %t", "Tag", "BanUpdated");
		else
			CReplyToCommand(iClient, "%t %t", "Tag", "BanNotCreated");
	}

	return Plugin_Handled;
}

Action Command_UnBan(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PluginDisabled");
		return Plugin_Handled;
	}

	if (iArgs != 1)
	{
		CReplyToCommand(iClient, "%t %t: sm_cvb_unban <#userid|name|steamid>", "Tag", "Usage");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
		return Plugin_Handled;
	}

	if (!g_bSQLTableExists)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "DBTableNotExists");
		return Plugin_Handled;
	}

	char sBuffer[100];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));

	if (!IsValidInput(sBuffer))
	{
		log(false, "[Command_UnBan] Invalid input detected: %s", sBuffer);
		CReplyToCommand(iClient, "%t %t", "Tag", "InvalidInput");
		return Plugin_Handled;
	}

	// use steamid to offline ban delete
	bool bIsOffline = ((StrContains(sBuffer, "STEAM_1", false) != -1) || (StrContains(sBuffer, "STEAM_0", false) != -1));
	int	 iTarget	= PlayerInGame(sBuffer);

	if (bIsOffline && iTarget == -1)
	{
		ReplaceString(sBuffer, sizeof(sBuffer), "STEAM_0", "STEAM_1", false);

		int iBans = GetBans(0, sBuffer, true);

		switch (iBans)
		{
			case -1:
			{
				CReplyToCommand(iClient, "%t %t", "Tag", "DBNoConnect");
				return Plugin_Handled;
			}
			case 0:
			{
				CReplyToCommand(iClient, "%t %t", "Tag", "ShowNoBan");
				return Plugin_Handled;
			}
			default:
			{
				if (iBans > 0)
				{
					if (DeleteBan(0, sBuffer, true))
						CReplyToCommand(iClient, "%t %t", "Tag", "BanDeleted");
					else
						CReplyToCommand(iClient, "%t %t", "Tag", "BanNotDeleted");
				}
			}
		}
		return Plugin_Handled;
	}
	else if (iTarget == -1)
		iTarget = FindTarget(iClient, sBuffer, true);

	if (iTarget == -1)
	{
		CReplyToCommand(iClient, "%t %t", "Tag", "PlayerNotFound");
		return Plugin_Handled;
	}

	// use target to online ban delete
	if (g_PlayersBans[iTarget].type == 0)
		CReplyToCommand(iClient, "%t %t", "Tag", "ShowNoBan");
	else
	{
		if (DeleteBan(iTarget))
			CReplyToCommand(iClient, "%t %t", "Tag", "BanDeleted");
		else
			CReplyToCommand(iClient, "%t %t", "Tag", "BanNotCreated");
	}
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	if (g_db == null)
		return;

	delete g_db;
	log(true, "[OnPluginEnd] Database connection closed.");
}

public void OnConfigsExecuted()
{
	if (g_db != null)
		return;

	ConnectDB("callvote", g_sTable);
}

public void OnClientAuthorized(int iClient, const char[] sAuth)
{
	if (!g_cvarEnable.BoolValue)
		return;

	if (IsFakeClient(iClient))
		return;

	if (!g_bSQLConnected || !g_bSQLTableExists)
		return;

	strcopy(g_PlayersBans[iClient].steamid2, MAX_AUTHID_LENGTH, sAuth);
	g_PlayersBans[iClient].type = 0;
	GetBans_Thread(iClient);
}

/*****************************************************************
			F O R W A R D   P L U G I N S
*****************************************************************/
public void CallVote_Start(int client, TypeVotes votes, int Target)
{
	if (!g_cvarEnable.BoolValue)
		return;

	if (!g_bSQLConnected || !g_bSQLTableExists)
		return;

	if (g_PlayersBans[client].type == 0)
		return;

	if (IsVoteEnabled(g_PlayersBans[client].type, votes))
	{
		char sReason[255];
		Format(sReason, sizeof(sReason), "%t", "VoteBlocked");
		CallVote_Reject(client, sReason);
		log(true, "[CallVote_Start] Vote blocked for %N %s", Target, g_PlayersBans[Target].steamid2);
		return;
	}
}

/*****************************************************************
			P L U G I N   F U N C T I O N S
*****************************************************************/

/**
 * Creates a ban for a player.
 *
 * @param iClient The client index of the banning player.
 * @param iTarget The client index of the player being banned.
 * @param iType The type of ban.
 * @param sSteamID The Steam ID of the player being banned. Optional if bOffline is true.
 * @param bOffline Specifies if the ban is an offline ban.
 * @return True if the ban was successfully created, false otherwise.
 */
bool CreateBan(int iClient, int iTarget, int iType, const char[] sSteamID = "", bool bOffline = false)
{
	char
		sAuth[MAX_AUTHID_LENGTH],
		sQuery[500];

	if (bOffline)
	{
		if (!IsValidInput(sSteamID))
		{
			log(false, "[CreateBan] Invalid SteamID detected: %s", sSteamID);
			return false;
		}
		strcopy(sAuth, sizeof(sAuth), sSteamID);
	}
	else
		strcopy(sAuth, sizeof(sAuth), g_PlayersBans[iTarget].steamid2);

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"INSERT INTO %s (authid, type, admin) VALUES ('%s', %d, '%s')",
						g_sTable, sAuth, iType, g_PlayersBans[iClient].steamid2);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"INSERT INTO %s (authid, type, admin) VALUES ('%s', %d, '%s')",
						g_sTable, sAuth, iType, g_PlayersBans[iClient].steamid2);
		}
		default:
		{
			log(false, "[CreateBan] Unknown SQL driver.");
			return false;
		}
	}

	if (!SQL_FastQuery(g_db, sQuery))
	{
		logErrorSQL(g_db, sQuery, "GetBans");
		return false;
	}

	if (bOffline)
		log(true, "[CreateBan] Offline ban created for %s | type: %d", sSteamID, iType);
	else
	{
		g_PlayersBans[iTarget].type = iType;
		log(true, "[CreateBan] Ban created for %N %s | type: %d", iTarget, g_PlayersBans[iTarget].steamid2, iType);
	}

	return true;
}

/**
 * Updates the ban information for a player.
 *
 * @param iClient The client index of the admin performing the update.
 * @param iTarget The client index of the player being banned.
 * @param iType The type of ban to apply.
 * @param sSteamID The SteamID of the player being banned (optional, used for offline bans).
 * @param bOffline Specifies whether the ban is an offline ban or not.
 * @return True if the ban update was successful, false otherwise.
 */
bool UpdateBan(int iClient, int iTarget, int iType, const char[] sSteamID = "", bool bOffline = false)
{
	char
		sAuth[MAX_AUTHID_LENGTH],
		sQuery[500];

	if (bOffline)
	{
		if (!IsValidInput(sSteamID))
		{
			log(false, "[UpdateBan] Invalid SteamID detected: %s", sSteamID);
			return false;
		}
		strcopy(sAuth, sizeof(sAuth), sSteamID);
	}
	else
		strcopy(sAuth, sizeof(sAuth), g_PlayersBans[iTarget].steamid2);

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"UPDATE `%s` SET `type` = %d, `admin` = '%s' WHERE `authid` = '%s'",
						g_sTable, iType, g_PlayersBans[iClient].steamid2, sAuth);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"UPDATE %s SET type = %d, admin = '%s' WHERE authid = '%s'",
						g_sTable, iType, g_PlayersBans[iClient].steamid2, sAuth);
		}
		default:
		{
			log(false, "[UpdateBan] Unknown SQL driver.");
			return false;
		}
	}

	if (!SQL_FastQuery(g_db, sQuery))
	{
		logErrorSQL(g_db, sQuery, "UpdateBan");
		return false;
	}

	if (bOffline)
		log(true, "[UpdateBan] Offline Ban updated for %s | type: %d", sSteamID, iType);
	else
	{
		g_PlayersBans[iTarget].type = iType;
		log(true, "[UpdateBan] Ban updated for %N %s | type: %d", iTarget, g_PlayersBans[iTarget].steamid2, iType);
	}

	return true;
}

/**
 * Deletes a ban.
 *
 * @param iTarget The index of the player ban to delete.
 * @param sSteamID The Steam ID of the player to delete the ban for. Defaults to an empty string.
 * @param bOffline Specifies whether the ban is an offline ban. Defaults to false.
 * @return True if the ban was successfully deleted, false otherwise.
 */
bool DeleteBan(int iTarget, const char[] sSteamID = "", bool bOffline = false)
{
	char
		sAuth[MAX_AUTHID_LENGTH],
		sQuery[500];

	if (bOffline)
	{
		if (!IsValidInput(sSteamID))
		{
			log(false, "[DeleteBan] Invalid SteamID detected: %s", sSteamID);
			return false;
		}
		strcopy(sAuth, sizeof(sAuth), sSteamID);
	}
	else
		strcopy(sAuth, sizeof(sAuth), g_PlayersBans[iTarget].steamid2);

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"DELETE FROM `%s` WHERE `authid` = '%s'", g_sTable, sAuth);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"DELETE FROM %s WHERE authid = '%s'", g_sTable, sAuth);
		}
		default:
		{
			log(false, "[DeleteBan] Unknown SQL driver.");
			return false;
		}
	}

	if (!SQL_FastQuery(g_db, sQuery))
	{
		logErrorSQL(g_db, sQuery, "DeleteBan");
		return false;
	}

	if (bOffline)
		log(true, "[DeleteBan] Offline Ban deleted for %s", sSteamID);
	else
	{
		g_PlayersBans[iTarget].type = 0;
		log(true, "[DeleteBan] Ban deleted for %N %s", iTarget, g_PlayersBans[iTarget].steamid2);
	}

	return true;
}

/**
 * Retrieves the ban type for a given client.
 *
 * @param iClient The client index.
 * @param sSteamID The SteamID of the client. Defaults to an empty string.
 * @param bOffline Specifies whether the client is offline. Defaults to false.
 * @return The ban type for the client. Returns 0 if the client is not banned.
 */
int GetBans(int iClient, const char[] sSteamID = "", bool bOffline = false)
{
	char
		sAuth[MAX_AUTHID_LENGTH],
		sQuery[500];

	if (bOffline)
	{
		if (!IsValidInput(sSteamID))
		{
			log(false, "[GetBans] Invalid SteamID detected: %s", sSteamID);
			return -1;
		}
		strcopy(sAuth, sizeof(sAuth), sSteamID);
	}
	else
		strcopy(sAuth, sizeof(sAuth), g_PlayersBans[iClient].steamid2);

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"SELECT `type` FROM `%s` WHERE `authid` = '%s'", g_sTable, sAuth);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"SELECT type FROM %s WHERE authid = '%s'", g_sTable, sAuth);
		}
		default:
		{
			log(false, "[GetBans] Unknown SQL driver.");
			return -1;
		}
	}

	DBResultSet QueryGetBans = SQL_Query(g_db, sQuery);
	if (QueryGetBans == null)
	{
		char sSQLError[255];
		SQL_GetError(g_db, sSQLError, sizeof(sSQLError));
		log(false, "[GetBans] SQL failed: %s", sSQLError);
		log(false, "[GetBans] Query dump: %s", sQuery);
		return -1;
	}

	int iTypeBan = 0;
	if (QueryGetBans.FetchRow())
	{
		iTypeBan = QueryGetBans.FetchInt(0);
	}

	delete QueryGetBans;
	return iTypeBan;
}

/**
 * Retrieves the ban type for a given client (Executes a query via a thread).
 *
 * @param iClient The client index.
 * @param sSteamID The SteamID of the client. Defaults to an empty string.
 * @param bOffline Specifies whether the client is offline. Defaults to false.
 * @return The ban type for the client. Returns 0 if the client is not banned.
 */
void GetBans_Thread(int iClient, const char[] sSteamID = "", bool bOffline = false)
{
	char
		sAuth[MAX_AUTHID_LENGTH],
		sQuery[500];

	if (bOffline)
		strcopy(sAuth, sizeof(sAuth), sSteamID);
	else
		strcopy(sAuth, sizeof(sAuth), g_PlayersBans[iClient].steamid2);

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"SELECT `type` FROM `%s` WHERE `authid` = '%s'", g_sTable, sAuth);
		}
		case SQL_SQLite:
		{
			g_db.Format(sQuery, sizeof(sQuery),
						"SELECT type FROM %s WHERE authid = '%s'", g_sTable, sAuth);
		}
		default:
		{
			log(false, "[GetBans_Thread] Unknown SQL driver.");
			return;
		}
	}

	g_db.Query(CallBack_GetBans_Thread, sQuery, GetClientUserId(iClient));
}

void CallBack_GetBans_Thread(Database db, DBResultSet results, const char[] error, any data)
{
	int iClient = GetClientOfUserId(data);

	if (iClient == CONSOLE || !IsClientInGame(iClient))
		return;

	if (results == null)
	{
		log(false, "[GetBans_Thread] SQL error: %s", error);
		return;
	}

	int iTypeBan = 0;
	if (results.FetchRow())
	{
		iTypeBan = results.FetchInt(0);
	}

	delete results;

	if (iTypeBan == 0)
	{
		log(true, "[GetBans_Thread] No bans found for client %N", iClient);
		return;
	}

	g_PlayersBans[iClient].type = iTypeBan;
	log(true, "[GetBans_Thread] Ban type %d found for client %N", iTypeBan, iClient);
}

/**
 * Displays a message containing the types of votes that are blocked.
 *
 * @param clientID The client ID to send the message to.
 * @param iTypeVotes The bitmask representing the types of votes that are blocked.
 * @param sName The name associated with the message.
 */
void VotesMessage(int clientID, int iTypeVotes, const char[] sName)
{
	char
		sMessage[300],
		sTraslation[32];

	int	 iBlockedVotes		 = 0;

	char voteTraslation[7][] = {
		"VOTE_CHANGEDIFFICULTY",
		"VOTE_RESTARTGAME",
		"VOTE_KICK",
		"VOTE_CHANGEMISSION",
		"VOTE_RETURNTOLOBBY",
		"VOTE_CHANGECHAPTER",
		"VOTE_CHANGEALLTALK"
	};

	for (int i = 0; i < 7; i++)
	{
		if (iTypeVotes & (1 << i))
		{
			AddSeparator(sMessage, sizeof(sMessage), iBlockedVotes);
			Format(sTraslation, sizeof(sTraslation), "%t", voteTraslation[i]);
			StrCat(sMessage, sizeof(sMessage), sTraslation);
			iBlockedVotes++;
		}
	}

	if (iBlockedVotes == 1)
		CReplyToCommand(clientID, "%t %t", "Tag", "ShowBan", sName, sMessage);
	else
		CReplyToCommand(clientID, "%t %t", "Tag", "ShowBans", sName, sMessage);
}

/**
 * Checks if a player with the specified Steam ID is currently in the game.
 *
 * @param sSteamID The Steam ID of the player to check.
 * @return The client index of the player if they are in the game, or -1 if not found.
 */
int PlayerInGame(const char[] sSteamID)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || IsFakeClient(i))
			continue;

		char sAuth[MAX_AUTHID_LENGTH];
		if (!GetClientAuthId(i, AuthId_Steam2, sAuth, MAX_AUTHID_LENGTH))
			continue;

		if (StrEqual(sAuth, sSteamID, false))
			return i;
	}
	return -1;
}

/**
 * Adds a separator to the given message if there are blocked votes.
 *
 * @param sMessage The message to add the separator to.
 * @param iSize The size of the message buffer.
 * @param iBlockedVotes The number of blocked votes.
 */
void AddSeparator(char[] sMessage, int iSize, int iBlockedVotes)
{
	if (iBlockedVotes > 0)
	{
		char sSeparator[2];
		Format(sSeparator, sizeof(sSeparator), "%t", "Separator");
		StrCat(sMessage, iSize, sSeparator);
	}
}

/**
 * Validates input to prevent SQL injection or invalid characters.
 *
 * @param input The input string to validate.
 * @return True if the input is valid, false otherwise.
 */
bool IsValidInput(const char[] input)
{
	static const char invalidChars[][] = { "'", ";", "--", "/*", "*/" };

	for (int i = 0; i < sizeof(invalidChars); i++)
	{
		if (StrContains(input, invalidChars[i], false) != -1)
			return false;
	}

	return true;
}

/**
 * Checks if a specific vote type is enabled based on the given vote flags.
 *
 * @param voteFlags The vote flags to check against.
 * @param type The type of vote to check.
 * @return True if the vote type is enabled, false otherwise.
 */
bool IsVoteEnabled(int voteFlags, TypeVotes type)
{
	int voteFlag;

	switch (type)
	{
		case ChangeDifficulty:
		{
			voteFlag = VOTE_CHANGEDIFFICULTY;
		}
		case RestartGame:
		{
			voteFlag = VOTE_RESTARTGAME;
		}
		case Kick:
		{
			voteFlag = VOTE_KICK;
		}
		case ChangeMission:
		{
			voteFlag = VOTE_CHANGEMISSION;
		}
		case ReturnToLobby:
		{
			voteFlag = VOTE_RETURNTOLOBBY;
		}
		case ChangeChapter:
		{
			voteFlag = VOTE_CHANGECHAPTER;
		}
		case ChangeAllTalk:
		{
			voteFlag = VOTE_CHANGEALLTALK;
		}
		default:
		{
			voteFlag = 0;
		}
	}

	return (voteFlags & voteFlag) != 0;
}

/**
 * @brief Checks if the given vote type flag is valid.
 *
 * This function verifies if the provided vote type flag is within the valid range
 * and if it matches any of the allowed vote types.
 *
 * @param iVotesFlag The vote type flag to check.
 * @return True if the vote type flag is valid, false otherwise.
 */
bool IsVoteTypeValid(int iVotesFlag)
{
	if (iVotesFlag < 1 || iVotesFlag > 127)
		return false;

	int allowedVotes = VOTE_CHANGEDIFFICULTY | VOTE_RESTARTGAME | VOTE_KICK | VOTE_CHANGEMISSION | VOTE_RETURNTOLOBBY | VOTE_CHANGECHAPTER | VOTE_CHANGEALLTALK;
	return (iVotesFlag & allowedVotes) == iVotesFlag;
}