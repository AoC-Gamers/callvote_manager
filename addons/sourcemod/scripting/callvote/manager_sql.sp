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

ConVar g_cvarSQL;

public void OPS_SQL()
{
	g_cvarSQL = CreateConVar("sm_cvm_sql", "0", "Enable SQL logging flags", FCVAR_NOTIFY, true, 0.0, true, 127.0);
	RegServerCmd("sm_cvm_createsql", Command_CreateSQL, "Create SQL tables for CallVoteManager");
}

Database Connect()
{
	char	 sError[255];
	Database db;

	if (SQL_CheckConfig("callvote"))
		db = SQL_Connect("callvote", true, sError, sizeof(sError));

	if (db == null)
		log("Could not connect to database: %s", sError);

	return db;
}

Action Command_CreateSQL(int args)
{
	Database db = Connect();
	if (db == null)
	{
		CReplyToCommand(CONSOLE, "%t Could not connect to database", "Tag");
		return Plugin_Handled;
	}

	char sQuery[600];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `callvote_log` ( \
        `id` int(6) NOT NULL auto_increment, \
        `authid` varchar(64) character set utf8 NOT NULL default '' COMMENT 'Client calling for a vote', \
        `created` int(11) NOT NULL default '0' COMMENT 'Creation date in unix format', \
        `type` int(6) NOT NULL default '0' COMMENT 'Voting type', \
        `authidTarget` varchar(64) character set utf8 NOT NULL default '' COMMENT 'Objective of a kick vote', \
        PRIMARY KEY(`id`)) \
		ENGINE = InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci");

	if (!SQL_FastQuery(db, sQuery))
	{
		char sError[255];
		SQL_GetError(db, sError, sizeof(sError));
		log("Query failed: %s", sError);
		log("Query dump: %s", sQuery);
		CReplyToCommand(CONSOLE, "%t Failed to query database", "Tag");
		return Plugin_Handled;
	}

	CReplyToCommand(CONSOLE, "%t Tables have been created.", "Tag");
	log("%t Tables have been created.", "Tag");

	delete db;
	return Plugin_Handled;
}

bool sqllog(TypeVotes type, int client, int target = 0)
{
	if (!g_cvarSQL.BoolValue)
		return false;

	Database db = Connect();
	if (db == null)
	{
		log("Could not connect to database");
		return false;
	}

	char
		sSteamID_Client[32],
		sSteamID_Target[32];

	GetClientAuthId(client, AuthId_Engine, sSteamID_Client, sizeof(sSteamID_Client));

	if (type == Kick)
		GetClientAuthId(target, AuthId_Engine, sSteamID_Target, sizeof(sSteamID_Target));
	else
		Format(sSteamID_Target, sizeof(sSteamID_Target), "");

	char sQuery[600];
	Format(sQuery, sizeof(sQuery), "INSERT INTO `callvote_log` (`authid`, `created`, `type`, `authidTarget`) VALUES ('%s', '%d', '%d', '%s')",
		   sSteamID_Client, GetTime(), view_as<int>(type), sSteamID_Target);

	if (!SQL_FastQuery(db, sQuery))
	{
		char sError[255];
		SQL_GetError(db, sError, sizeof(sError));
		log("Query failed: %s", sError);
		log("Query dump: %s", sQuery);
		return false;
	}

	delete db;
	return true;
}

/*
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `callvote_bans` ( \
		`bid` int(6) NOT NULL auto_increment, \
		`ip` varchar(32) default NULL, \
		`authid` varchar(64) character set utf8 NOT NULL default '', \
		`name` varchar(128) character set utf8 NOT NULL default 'unnamed', \
		`created` int(11) NOT NULL default '0', \
		`ends` int(11) NOT NULL default '0', \
		`length` int(10) NOT NULL default '0', \
		`reason` text character set utf8 NOT NULL, \
		`aid` int(6) NOT NULL default '0', \
		`adminIp` varchar(32) NOT NULL default '', \
		`sid` int(6) NOT NULL default '0', \
		`country` varchar(4) default NULL, \
		`RemovedBy` int(8) NULL, \
		`RemoveType` VARCHAR(3) NULL, \
		`RemovedOn` int(10) NULL, \
		`type` TINYINT NOT NULL DEFAULT '0', \
		`ureason` text, \
		PRIMARY KEY(`bid`), \
		KEY `sid` (`sid`), \
		FULLTEXT KEY `reason` (`reason`), \
		FULLTEXT KEY `authid_2` (`authid`), \
		KEY `type_authid` (`type`,`authid`), \
		KEY `type_ip` (`type`,`ip`)) \
		ENGINE = InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci");
*/