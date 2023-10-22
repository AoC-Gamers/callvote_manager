/**
 * vim: set ts=4 sw=4 tw=99 noet :
 * =============================================================================
 * SourceMod (C)2004-2014 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This file is part of the SourceMod/SourcePawn SDK.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#if defined _callvotemanager_sql_included
	#endinput
#endif
#define _callvotemanager_sql_included

ConVar		g_cvarSQL;
DBStatement hPrepareQuery = null;
Database	hGetKick;

public void OPS_SQL()
{
	g_cvarSQL = CreateConVar("sm_cvkl_sql", "0", "Enables kick counter registration to the database, if disabled it uses local memory.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	RegServerCmd("sm_cvkl_createsql", Command_CreateSQL, "Create SQL tables for CallVote KickLimit");

	hGetKick = Connect();
	if (hGetKick == null)
		log("Could not connect to database: hGetKick");
}

Database Connect()
{
	char	 sError[255];
	Database hDataBase;

	if (SQL_CheckConfig("callvote"))
		hDataBase = SQL_Connect("callvote", true, sError, sizeof(sError));

	if (hDataBase == null)
		log("Could not connect to database: %s", sError);

	return hDataBase;
}

Action Command_CreateSQL(int iArgs)
{
	Database hDataBase = Connect();
	if (hDataBase == null)
	{
		CReplyToCommand(CONSOLE, "%t Could not connect to database", "Tag");
		return Plugin_Handled;
	}

	char sQuery[600];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `callvote_kicklimit` ( \
        `id` int(6) NOT NULL auto_increment, \
        `authid` varchar(64) character set utf8 NOT NULL default '' COMMENT 'Client calling for a vote', \
        `created` int(11) NOT NULL default '0' COMMENT 'Creation date in unix format', \
        `authidTarget` varchar(64) character set utf8 NOT NULL default '' COMMENT 'Objective of a kick vote', \
        PRIMARY KEY(`id`)) \
		ENGINE = InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci");

	if (!SQL_FastQuery(hDataBase, sQuery))
	{
		char sError[255];
		SQL_GetError(hDataBase, sError, sizeof(sError));
		log("Query failed: %s", sError);
		log("Query dump: %s", sQuery);
		CReplyToCommand(CONSOLE, "%t Failed to query database", "Tag");
		return Plugin_Handled;
	}

	CReplyToCommand(CONSOLE, "%t Tables have been created.", "Tag");
	log("%t Tables have been created.", "Tag");

	delete hDataBase;
	return Plugin_Handled;
}

bool sqlinsert(int iClient, int iTarget)
{
	if (!g_cvarSQL.BoolValue)
		return false;

	Database hDataBase = Connect();
	if (hDataBase == null)
	{
		log("Could not connect to database");
		return false;
	}

	char
		sSteamID_Client[MAX_AUTHID_LENGTH],
		sSteamID_Target[MAX_AUTHID_LENGTH];

	GetClientAuthId(iClient, AuthId_Engine, sSteamID_Client, MAX_AUTHID_LENGTH);
	GetClientAuthId(iTarget, AuthId_Engine, sSteamID_Target, MAX_AUTHID_LENGTH);

	char sQuery[600];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `callvote_kicklimit` (`authid`, `created`, `authidTarget`) VALUES ('%s', '%d', '%s')", sSteamID_Client, GetTime(), sSteamID_Target);

	if (!SQL_FastQuery(hDataBase, sQuery))
	{
		char sError[255];
		SQL_GetError(hDataBase, sError, sizeof(sError));
		log("Query failed: %s", sError);
		log("Query dump: %s", sQuery);
		return false;
	}

	delete hDataBase;
	return true;
}

bool GetCountKick(Database hDataBase, int iClient, const char[] sSteamID)
{
	char error[255];

	/* Check if we haven't already created the statement */
	if (hPrepareQuery == null)
	{
		hPrepareQuery = SQL_PrepareQuery(hDataBase, "SELECT COUNT(*) FROM callvote_kicklimit WHERE created >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 DAY)) AND authid = ?", error, sizeof(error));
		if (hPrepareQuery == null)
		{
			log("Failed to Prepare Query: %s", error);
			return false;
		}
	}

	hPrepareQuery.BindString(0, sSteamID, false);
	if (!SQL_Execute(hPrepareQuery))
	{
		SQL_GetError(hPrepareQuery, error, sizeof(error));
		log("Failed to execute query: %s", error);
		return false;
	}

	/* Get some info here */
	while (SQL_FetchRow(hPrepareQuery))
	{
		g_Players[iClient].Kick = SQL_FetchInt(hPrepareQuery, 0);
	}
	return true;
}