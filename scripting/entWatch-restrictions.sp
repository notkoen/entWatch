//====================================================================================================
//
// Name: [entWatch] Restrictions
// Author: zaCade & Prometheum
// Description: Handle the restrictions of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: 1.10.0.6531 or above
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs_stocks>
#include <entWatch_core>

/* BOOLEANS */
bool g_bRestrictedTemp[MAXPLAYERS+1];

/* INTERGERS */
int g_iRestrictIssued[MAXPLAYERS+1];
int g_iRestrictLength[MAXPLAYERS+1];
int g_iRestrictExpire[MAXPLAYERS+1];

/* STRINGMAPS */
StringMap g_hTrie_Storage;

/* COOKIES */
Cookie_Stocks g_hCookie_RestrictIssued;
Cookie_Stocks g_hCookie_RestrictExpire;
Cookie_Stocks g_hCookie_RestrictLength;

/* FORWARDS */
GlobalForward g_hFwd_OnClientRestricted;
GlobalForward g_hFwd_OnClientUnrestricted;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Restrictions",
	author       = "zaCade & Prometheum",
	description  = "Handle the restrictions of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int errorSize)
{
	CreateNative("EW_ClientRestrict",   Native_ClientRestrict);
	CreateNative("EW_ClientUnrestrict", Native_ClientUnrestrict);
	CreateNative("EW_ClientRestricted", Native_ClientRestricted);

	RegPluginLibrary("entWatch-restrictions");
	return APLRes_Success;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("entWatch.phrases");

	g_hFwd_OnClientRestricted   = new GlobalForward("EW_OnClientRestricted",   ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hFwd_OnClientUnrestricted = new GlobalForward("EW_OnClientUnrestricted", ET_Ignore, Param_Cell, Param_Cell);

	g_hCookie_RestrictIssued = new Cookie_Stocks("EW_RestrictIssued", "", CookieAccess_Private);
	g_hCookie_RestrictExpire = new Cookie_Stocks("EW_RestrictExpire", "", CookieAccess_Private);
	g_hCookie_RestrictLength = new Cookie_Stocks("EW_RestrictLength", "", CookieAccess_Private);

	g_hTrie_Storage = new StringMap();

	RegAdminCmd("sm_eban",   Command_ClientRestrict,   ADMFLAG_BAN);
	RegAdminCmd("sm_eunban", Command_ClientUnrestrict, ADMFLAG_UNBAN);

	RegConsoleCmd("sm_restrictions", Command_DisplayRestrictions);
	RegConsoleCmd("sm_status",       Command_DisplayStatus);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
			OnClientPutInServer(client);

		if (AreClientCookiesCached(client))
			OnClientCookiesCached(client);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	g_hTrie_Storage.Clear();
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	char sAddress[32];
	GetClientIP(client, sAddress, sizeof(sAddress));

	bool bRestrictedTemp;
	if (g_hTrie_Storage.GetValue(sAddress, bRestrictedTemp))
	{
		g_bRestrictedTemp[client] = bRestrictedTemp;
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientCookiesCached(int client)
{
	g_iRestrictIssued[client] = g_hCookie_RestrictIssued.GetInt(client);
	g_iRestrictExpire[client] = g_hCookie_RestrictExpire.GetInt(client);
	g_iRestrictLength[client] = g_hCookie_RestrictLength.GetInt(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int client)
{
	if (g_bRestrictedTemp[client])
	{
		char sAddress[32];
		GetClientIP(client, sAddress, sizeof(sAddress));

		g_hTrie_Storage.SetArray(sAddress, g_bRestrictedTemp[client], true);
	}

	g_bRestrictedTemp[client] = false;
	g_iRestrictIssued[client] = 0;
	g_iRestrictExpire[client] = 0;
	g_iRestrictLength[client] = 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_ClientRestrict(int client, int args)
{
	if (!GetCmdArgs())
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Usage: sm_eban <#userid/name> [duration]");
		return Plugin_Handled;
	}

	char sArguments[2][32];
	GetCmdArg(1, sArguments[0], sizeof(sArguments[]));
	GetCmdArg(2, sArguments[1], sizeof(sArguments[]));

	int target;
	if ((target = FindTarget(client, sArguments[0], true)) == -1)
		return Plugin_Handled;

	if (GetCmdArgs() >= 2)
	{
		int length = StringToInt(sArguments[1]);

		if (ClientRestrict(client, target, length))
		{
			if (length)
			{
				PrintToChatAll("\x04[entWatch] \x01%N restricted %N for %d minutes.", client, target, length);
				LogAction(client, target, "%L restricted %L for %d minutes.", client, target, length);
			}
			else
			{
				PrintToChatAll("\x04[entWatch] \x01%N restricted %N permanently.", client, target);
				LogAction(client, target, "%L restricted %L permanently.", client, target);
			}
		}
	}
	else
	{
		if (ClientRestrict(client, target, -1))
		{
			PrintToChatAll("\x04[entWatch] \x01%N restricted %N temporarily.", client, target);
			LogAction(client, target, "%L restricted %L temporarily.", client, target);
		}
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_ClientUnrestrict(int client, int args)
{
	if (!GetCmdArgs())
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Usage: sm_eunban <#userid/name>");
		return Plugin_Handled;
	}

	char sArguments[1][32];
	GetCmdArg(1, sArguments[0], sizeof(sArguments[]));

	int target;
	if ((target = FindTarget(client, sArguments[0], true)) == -1)
		return Plugin_Handled;

	if (ClientUnrestrict(client, target))
	{
		PrintToChatAll("\x04[entWatch] \x01%N unrestricted %N.", client, target);
		LogAction(client, target, "%L unrestricted %L.", client, target);
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayRestrictions(int client, int args)
{
	char aBuf[1024];
	char aBuf2[MAX_NAME_LENGTH];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (ClientRestricted(i))
			{
				GetClientName(i, aBuf2, sizeof(aBuf2));
				StrCat(aBuf, sizeof(aBuf), aBuf2);
				StrCat(aBuf, sizeof(aBuf), ", ");
			}
		}
	}

	if (strlen(aBuf))
	{
		aBuf[strlen(aBuf) - 2] = 0;
		ReplyToCommand(client, "\x04[entWatch] \x01Currently restricted clients: %s", aBuf);
	}
	else
		ReplyToCommand(client, "\x04[entWatch] \x01Currently restricted clients: none");

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayStatus(int client, int args)
{
	if (CheckCommandAccess(client, "", ADMFLAG_BAN) && GetCmdArgs())
	{
		char sArguments[1][32];
		GetCmdArg(1, sArguments[0], sizeof(sArguments[]));

		int target;
		if ((target = FindTarget(client, sArguments[0], true)) == -1)
			return Plugin_Handled;

		if (!AreClientCookiesCached(target))
		{
			ReplyToCommand(client, "\x04[entWatch] \x01%N their cookies are still loading.", target);
			return Plugin_Handled;
		}
		else if (g_bRestrictedTemp[target])
		{
			ReplyToCommand(client, "\x04[entWatch] \x01%N is currently temporarily restricted.", target);
			return Plugin_Handled;
		}
		else if (g_iRestrictIssued[target] && g_iRestrictExpire[target] == 0)
		{
			ReplyToCommand(client, "\x04[entWatch] \x01%N is currently permanently restricted.", target);
			return Plugin_Handled;
		}
		else if (g_iRestrictIssued[target] && g_iRestrictExpire[target] >= GetTime())
		{
			char sTimeRemaining[64];
			int iTimeRemaining = g_iRestrictExpire[target] - GetTime();

			int iDays    = (iTimeRemaining / 86400);
			int iHours   = (iTimeRemaining / 3600) % 24;
			int iMinutes = (iTimeRemaining / 60) % 60;
			int iSeconds = (iTimeRemaining % 60);

			if (iDays)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Days %d Hours %d Minutes %d Seconds", iDays, iHours, iMinutes, iSeconds);
			else if (iHours)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Hours %d Minutes %d Seconds", iHours, iMinutes, iSeconds);
			else if (iMinutes)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Minutes %d Seconds", iMinutes, iSeconds);
			else
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Seconds", iSeconds);

			ReplyToCommand(client, "\x04[entWatch] \x01%N is currently restricted for another: %s.", target, sTimeRemaining);
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "\x04[entWatch] \x01%N is currently not restricted.", target);
			return Plugin_Handled;
		}
	}
	else
	{
		if (!AreClientCookiesCached(client))
		{
			ReplyToCommand(client, "\x04[entWatch] \x01Your cookies are still loading.");
			return Plugin_Handled;
		}
		else if (g_bRestrictedTemp[client])
		{
			ReplyToCommand(client, "\x04[entWatch] \x01You are currently temporarily restricted.");
			return Plugin_Handled;
		}
		else if (g_iRestrictIssued[client] && g_iRestrictExpire[client] == 0)
		{
			ReplyToCommand(client, "\x04[entWatch] \x01You are currently permanently restricted.");
			return Plugin_Handled;
		}
		else if (g_iRestrictIssued[client] && g_iRestrictExpire[client] >= GetTime())
		{
			char sTimeRemaining[64];
			int iTimeRemaining = g_iRestrictExpire[client] - GetTime();

			int iDays    = (iTimeRemaining / 86400);
			int iHours   = (iTimeRemaining / 3600) % 24;
			int iMinutes = (iTimeRemaining / 60) % 60;
			int iSeconds = (iTimeRemaining % 60);

			if (iDays)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Days %d Hours %d Minutes %d Seconds", iDays, iHours, iMinutes, iSeconds);
			else if (iHours)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Hours %d Minutes %d Seconds", iHours, iMinutes, iSeconds);
			else if (iMinutes)
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Minutes %d Seconds", iMinutes, iSeconds);
			else
				Format(sTimeRemaining, sizeof(sTimeRemaining), "%d Seconds", iSeconds);

			ReplyToCommand(client, "\x04[entWatch] \x01You are currently restricted for another: %s.", sTimeRemaining);
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "\x04[entWatch] \x01You are currently not restricted.");
			return Plugin_Handled;
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemWeaponCanInteract(int iClient, CItem hItem)
{
	return !ClientRestricted(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemButtonCanInteract(int iClient, CItemButton hItemButton)
{
	return !ClientRestricted(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemTriggerCanInteract(int iClient, CItemTrigger hItemTrigger)
{
	return !ClientRestricted(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool ClientRestrict(int client, int target, int length)
{
	if (!IsValidClient(client) || !IsValidClient(target) || !AreClientCookiesCached(target) || ClientRestricted(target))
		return false;

	if (length == -1)
	{
		g_bRestrictedTemp[target] = true;
	}
	else if (length == 0)
	{
		g_bRestrictedTemp[target] = false;
		g_iRestrictIssued[target] = GetTime();
		g_iRestrictExpire[target] = 0;
		g_iRestrictLength[target] = 0;

		g_hCookie_RestrictIssued.SetInt(target, GetTime());
		g_hCookie_RestrictExpire.SetInt(target, 0);
		g_hCookie_RestrictLength.SetInt(target, 0);
	}
	else
	{
		g_bRestrictedTemp[target] = false;
		g_iRestrictIssued[target] = GetTime();
		g_iRestrictExpire[target] = GetTime() + (length * 60);
		g_iRestrictLength[target] = length;

		g_hCookie_RestrictIssued.SetInt(target, GetTime());
		g_hCookie_RestrictExpire.SetInt(target, GetTime() + (length * 60));
		g_hCookie_RestrictLength.SetInt(target, length);
	}

	Call_StartForward(g_hFwd_OnClientRestricted);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_PushCell(length);
	Call_Finish();

	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool ClientUnrestrict(int client, int target)
{
	if (!IsValidClient(client) || !IsValidClient(target) || !AreClientCookiesCached(target) || !ClientRestricted(target))
		return false;

	g_bRestrictedTemp[target] = false;
	g_iRestrictIssued[target] = 0;
	g_iRestrictExpire[target] = 0;
	g_iRestrictLength[target] = 0;

	g_hCookie_RestrictIssued.SetInt(target, 0);
	g_hCookie_RestrictExpire.SetInt(target, 0);
	g_hCookie_RestrictLength.SetInt(target, 0);

	Call_StartForward(g_hFwd_OnClientUnrestricted);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_Finish();

	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool ClientRestricted(int client)
{
	if (!IsValidClient(client))
		return false;

	//Block them when loading cookies..
	if (!AreClientCookiesCached(client))
		return true;

	//Temporary restriction.
	if (g_bRestrictedTemp[client])
		return true;

	//Permanent restriction.
	if (g_iRestrictIssued[client] && g_iRestrictExpire[client] == 0)
		return true;

	//Normal restriction.
	if (g_iRestrictIssued[client] && g_iRestrictExpire[client] >= GetTime())
		return true;

	return false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool IsValidClient(int client)
{
	return ((1 <= client <= MaxClients) && IsClientConnected(client));
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public int Native_ClientRestrict(Handle hPlugin, int numParams)
{
	return ClientRestrict(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3));
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public int Native_ClientUnrestrict(Handle hPlugin, int numParams)
{
	return ClientUnrestrict(GetNativeCell(1), GetNativeCell(2));
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public int Native_ClientRestricted(Handle hPlugin, int numParams)
{
	return ClientRestricted(GetNativeCell(1));
}
