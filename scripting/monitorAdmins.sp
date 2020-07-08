
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define IDAYS 26

#define VERSION "1.0.0"

int g_iPlayTimeSpec[MAXPLAYERS+1] = 0;
int g_iPlayTimeT[MAXPLAYERS+1] = 0;
int g_iPlayTimeCT[MAXPLAYERS+1] = 0;

bool g_bChecked[MAXPLAYERS + 1];

char g_sSQLBuffer[3096];

bool g_bIsMySQl;

// DB handle
Handle g_hDB = INVALID_HANDLE;
Handle gF_OnInsertNewPlayer;

public Plugin myinfo = {
	name = "Monitoring admin playtime",
	author = "TheFlyingApple",
	description = "Monitor admin playtime - Based on Mostactive plugin by Franc1sco",
	version = VERSION,
	url = "http://hjemezez.dk"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char [] error, int err_max)
{
	gF_OnInsertNewPlayer = CreateGlobalForward("MostActive_OnInsertNewPlayer", ET_Event, Param_Cell);

	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_monitoradmins_version", VERSION, "version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	SQL_TConnect(OnSQLConnect, "monitorAdmins");
}

public int OnSQLConnect(Handle owner, Handle hndl, char [] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("Database failure: %s", error);
		
		SetFailState("Databases dont work");
	}
	else
	{
		g_hDB = hndl;
		
		SQL_GetDriverIdent(SQL_ReadDriver(g_hDB), g_sSQLBuffer, sizeof(g_sSQLBuffer));
		g_bIsMySQl = StrEqual(g_sSQLBuffer,"mysql", false) ? true : false;
		
		if(g_bIsMySQl)
		{
			Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "CREATE TABLE IF NOT EXISTS `monitorAdmins` (`playername` varchar(128) NOT NULL, `steamid` varchar(32) PRIMARY KEY NOT NULL,`last_accountuse` int(64) NOT NULL, `timeCT` INT( 16 ), `timeTT` INT( 16 ),`timeSPE` INT( 16 ), `total` INT( 16 ))");
			
			SQL_TQuery(g_hDB, OnSQLConnectCallback, g_sSQLBuffer);
		}
		else
		{
			Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "CREATE TABLE IF NOT EXISTS monitorAdmins (playername varchar(128) NOT NULL, steamid varchar(32) PRIMARY KEY NOT NULL,last_accountuse int(64) NOT NULL, timeCT INTEGER, timeTT INTEGER, timeSPE INTEGER, total INTEGER)");
			
			SQL_TQuery(g_hDB, OnSQLConnectCallback, g_sSQLBuffer);
		}
		PruneDatabase();
	}
}

public int OnSQLConnectCallback(Handle owner, Handle hndl, char [] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("Query failure: %s", error);
		return;
	}
	
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			OnClientPostAdminCheck(client);
		}
	}
}

public void InsertSQLNewPlayer(int client)
{
	char query[255], steamid[32];
	GetClientAuthId(client, AuthId_Steam2,steamid, sizeof(steamid));
	int userid = GetClientUserId(client);
	
	char Name[MAX_NAME_LENGTH+1];
	char SafeName[(sizeof(Name)*2)+1];
	if(!GetClientName(client, Name, sizeof(Name)))
		Format(SafeName, sizeof(SafeName), "<noname>");
	else
	{
		TrimString(Name);
		SQL_EscapeString(g_hDB, Name, SafeName, sizeof(SafeName));
	}
	
	Format(query, sizeof(query), "INSERT INTO monitorAdmins(playername, steamid, last_accountuse, timeCT, timeTT, timeSPE, total) VALUES('%s', '%s', '%d', '0', '0', '0', '0');", SafeName, steamid, GetTime());
	SQL_TQuery(g_hDB, SaveSQLPlayerCallback, query, userid);
	g_iPlayTimeCT[client] = 0;
	g_iPlayTimeT[client] = 0;
	g_iPlayTimeSpec[client] = 0;
	
	Call_StartForward(gF_OnInsertNewPlayer);
	Call_PushCell(client);
	Call_Finish();
	
	g_bChecked[client] = true;
}

public int SaveSQLPlayerCallback(Handle owner, Handle hndl, char [] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("Query failure: %s", error);
	}
}

public void CheckSQLSteamID(int client)
{
	char query[255], steamid[32];
	GetClientAuthId(client, AuthId_Steam2,steamid, sizeof(steamid) );
	
	Format(query, sizeof(query), "SELECT timeCT, timeTT, timeSPE FROM monitorAdmins WHERE steamid = '%s'", steamid);
	SQL_TQuery(g_hDB, CheckSQLSteamIDCallback, query, GetClientUserId(client));
}

public int CheckSQLSteamIDCallback(Handle owner, Handle hndl, char [] error, any data)
{
	int client;
	
	/* Make sure the client didn't disconnect while the thread was running */
	
	if((client = GetClientOfUserId(data)) == 0)
	{
		return;
	}
	
	if(hndl == INVALID_HANDLE)
	{
		LogError("Query failure: %s", error);
		return;
	}
	if(!SQL_GetRowCount(hndl) || !SQL_FetchRow(hndl)) 
	{
		InsertSQLNewPlayer(client);
		return;
	}
	
	g_iPlayTimeCT[client] = SQL_FetchInt(hndl, 0);
	g_iPlayTimeT[client] = SQL_FetchInt(hndl, 1);
	g_iPlayTimeSpec[client] = SQL_FetchInt(hndl, 2);
	g_bChecked[client] = true;
}

public void SaveSQLCookies(int client)
{
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2,steamid, sizeof(steamid) );
	char Name[MAX_NAME_LENGTH+1];
	char SafeName[(sizeof(Name)*2)+1];
	if(!GetClientName(client, Name, sizeof(Name)))
		Format(SafeName, sizeof(SafeName), "<noname>");
	else
	{
		TrimString(Name);
		SQL_EscapeString(g_hDB, Name, SafeName, sizeof(SafeName));
	}	

	char buffer[3096];
	Format(buffer, sizeof(buffer), "UPDATE monitorAdmins SET last_accountuse = %d, playername = '%s',timeCT = '%i',timeTT = '%i', timeSPE = '%i',total = '%i' WHERE steamid = '%s';",GetTime(), SafeName, g_iPlayTimeCT[client],g_iPlayTimeT[client],g_iPlayTimeSpec[client],g_iPlayTimeCT[client]+g_iPlayTimeT[client]+g_iPlayTimeSpec[client], steamid);
	SQL_TQuery(g_hDB, SaveSQLPlayerCallback, buffer);
	g_bChecked[client] = false;
}

public void OnPluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			OnClientDisconnect(client);
		}
	}
}

public void OnClientDisconnect(int client)
{
	if( !IsFakeClient(client) && g_bChecked[client] && CheckCommandAccess(client, "monitorAdmin_On_This_player", ADMFLAG_GENERIC, false) ) SaveSQLCookies(client);
}

public void OnClientPostAdminCheck(int client)
{
	if( !IsFakeClient(client) && CheckCommandAccess(client, "monitorAdmin_On_This_player", ADMFLAG_GENERIC, false) ) CheckSQLSteamID(client);
}

public void PruneDatabase()
{
	if(g_hDB == INVALID_HANDLE)
	{
		return;
	}

	int maxlastaccuse;
	maxlastaccuse = GetTime() - (IDAYS * 86400);

	char buffer[1024];

	if(g_bIsMySQl)
		Format(buffer, sizeof(buffer), "DELETE FROM `monitorAdmins` WHERE `last_accountuse`<'%d' AND `last_accountuse`>'0';", maxlastaccuse);
	else
		Format(buffer, sizeof(buffer), "DELETE FROM monitorAdmins WHERE last_accountuse<'%d' AND last_accountuse>'0';", maxlastaccuse);

	SQL_TQuery(g_hDB, PruneDatabaseCallback, buffer);
}

public int PruneDatabaseCallback(Handle owner, Handle hndl, char [] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogMessage("Query failure: %s", error);
	}
	//LogMessage("Prune Database successful");
}

public void OnMapStart()
{
	CreateTimer(1.0, PlayTimeTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action PlayTimeTimer(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++) 
	{
		if(IsClientInGame(i))
		{
			int team = GetClientTeam(i);
			
			if(team == 2)
			{
				++g_iPlayTimeT[i];
			}
			else if(team == 3)
			{
				++g_iPlayTimeCT[i];
			}
			else
			{
				++g_iPlayTimeSpec[i];
			}
		}
	}
}