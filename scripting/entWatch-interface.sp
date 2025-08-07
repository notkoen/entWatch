//====================================================================================================
//
// Name: [entWatch] Interface
// Author: zaCade & Prometheum
// Description: Handle the interface of [entWatch]
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
bool g_bInterfaceHidden[MAXPLAYERS+1];

/* COOKIES */
Cookie_Stocks g_hCookie_InterfaceHidden;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Interface",
	author       = "zaCade & Prometheum",
	description  = "Handle the interface of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("entWatch.phrases");

	g_hCookie_InterfaceHidden = new Cookie_Stocks("EW_InterfaceHidden", "", CookieAccess_Private);

	RegConsoleCmd("sm_hud", Command_ToggleHUD);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	CreateTimer(1.0, OnDisplayHUD, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientCookiesCached(int iClient)
{
	g_bInterfaceHidden[iClient] = g_hCookie_InterfaceHidden.GetBool(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int iClient)
{
	g_bInterfaceHidden[iClient] = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_ToggleHUD(int iClient, int iArgs)
{
	g_bInterfaceHidden[iClient] = !g_bInterfaceHidden[iClient];

	if (g_bInterfaceHidden[iClient])
	{
		g_hCookie_InterfaceHidden.SetBool(iClient, true);

		ReplyToCommand(iClient, "\x04[entWatch] \x01You will now no longer see the HUD.");
		return Plugin_Handled;
	}
	else
	{
		g_hCookie_InterfaceHidden.SetBool(iClient, false);

		ReplyToCommand(iClient, "\x04[entWatch] \x01You will now see the HUD again.");
		return Plugin_Handled;
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool FormatButtonCooldown(char[] sBuffer, const int iMaxLength, CItemButton hItemButton)
{
	switch (hItemButton.hConfigButton.iMode)
	{
		case EW_BUTTON_MODE_COOLDOWN:
		{
			if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "R");
				return true;
			}
		}
		case EW_BUTTON_MODE_MAXUSES:
		{
			if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else if (hItemButton.iCurrentUses < hItemButton.hConfigButton.iMaxUses)
			{
				Format(sBuffer, iMaxLength, "%d/%d", hItemButton.iCurrentUses, hItemButton.hConfigButton.iMaxUses);
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "D");
				return true;
			}
		}
		case EW_BUTTON_MODE_COOLDOWN_CHARGES:
		{
			if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "%d/%d", hItemButton.iCurrentUses, hItemButton.hConfigButton.iMaxUses);
				return true;
			}
		}
	}

	return false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool FormatItemCooldowns(char[] sBuffer, const int iMaxLength, CItem hItem)
{
	bool bHasCooldown;

	for (int iItemButtonID; iItemButtonID < hItem.hButtons.Length; iItemButtonID++)
	{
		CItemButton hItemButton = hItem.hButtons.Get(iItemButtonID);

		if (hItemButton.hConfigButton.bShowCooldown)
		{
			char sCooldown[8];
			bool bCooldown = FormatButtonCooldown(sCooldown, sizeof(sCooldown), hItemButton);

			if (bCooldown)
			{
				if (!bHasCooldown)
				{
					bHasCooldown = true;

					StrCat(sBuffer, iMaxLength, sCooldown);
				}
				else
				{
					StrCat(sBuffer, iMaxLength, "|");
					StrCat(sBuffer, iMaxLength, sCooldown);
				}
			}
		}
	}

	return bHasCooldown;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock Action OnDisplayHUD(Handle hTimer)
{
	int iHUDPages[3];
	char sHUDPages[3][8][255];

	ArrayList hItems = EW_GetItemsArray();

	for (int iItemID; iItemID < hItems.Length; iItemID++)
	{
		CItem hItem = hItems.Get(iItemID);

		if (hItem.hConfig.bShowInterface && hItem.iClient != INVALID_ENT_REFERENCE)
		{
			char sShort[16];
			hItem.hConfig.GetShort(sShort, sizeof(sShort));

			char sCooldowns[16];
			bool bCooldowns = FormatItemCooldowns(sCooldowns, sizeof(sCooldowns), hItem);

			char sLine[64];

			if (bCooldowns)
			{
				Format(sLine, sizeof(sLine), "%s [%s]: %N", sShort, sCooldowns, hItem.iClient);
			}
			else
			{
				Format(sLine, sizeof(sLine), "%s [N/A]: %N", sShort, hItem.iClient);
			}

			switch (GetClientTeam(hItem.iClient))
			{
				case (2):
				{
					if (strlen(sHUDPages[1][iHUDPages[1]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][])) iHUDPages[1]++;

					StrCat(sHUDPages[1][iHUDPages[1]], sizeof(sHUDPages[][]), sLine);
					StrCat(sHUDPages[1][iHUDPages[1]], sizeof(sHUDPages[][]), "\n");
				}
				case (3):
				{
					if (strlen(sHUDPages[2][iHUDPages[2]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][])) iHUDPages[2]++;

					StrCat(sHUDPages[2][iHUDPages[2]], sizeof(sHUDPages[][]), sLine);
					StrCat(sHUDPages[2][iHUDPages[2]], sizeof(sHUDPages[][]), "\n");
				}
			}

			if (strlen(sHUDPages[0][iHUDPages[0]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][])) iHUDPages[0]++;

			StrCat(sHUDPages[0][iHUDPages[0]], sizeof(sHUDPages[][]), sLine);
			StrCat(sHUDPages[0][iHUDPages[0]], sizeof(sHUDPages[][]), "\n");
		}
	}

	static int iPageInterval;
	static int iPageCurrent[3];

	if (iPageInterval >= 5)
	{
		for (int iPageID; iPageID < 3; iPageID++)
		{
			if (iPageCurrent[iPageID] >= iHUDPages[iPageID])
				iPageCurrent[iPageID] = 0;
			else
				iPageCurrent[iPageID]++;
		}

		iPageInterval = 0;
	}
	else
		iPageInterval++;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || (IsFakeClient(iClient) && !IsClientSourceTV(iClient)) || g_bInterfaceHidden[iClient])
			continue;

		int iPagePanel;

		switch (GetClientTeam(iClient))
		{
			case (2): iPagePanel = 1;
			case (3): iPagePanel = 2;
		}

		if (sHUDPages[iPagePanel][iPageCurrent[iPagePanel]][0])
		{
			/*
			if (GetClientMenu(iClient) == MenuSource_None)
			{
				/
				Menu hMenu = new Menu(PanelHandler_HUD);
				hMenu.ExitButton = true;
				hMenu.AddItem("", sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
				hMenu.Display(iClient, MENU_TIME_FOREVER);
				*

				/
				Panel hPanel = new Panel();
				hPanel.DrawText(sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
				hPanel.Send(iClient, PanelHandler_HUD, MENU_TIME_FOREVER);
				*
			}
			*/

			Handle hMessage = StartMessageOne("KeyHintText", iClient);

			if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
			{
				PbAddString(hMessage, "hints", sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
			}
			else
			{
				// Byte: message amount.
				// String: message string.
				BfWriteByte(hMessage, 1);
				BfWriteString(hMessage, sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
			}

			EndMessage();
		}
	}

	return Plugin_Continue;
}

public void PanelHandler_HUD(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case (MenuAction_Select):
		{
			// param1 = client
			// param2 = key pressed

			PrintToChatAll("MenuAction_Select: %N -> %d", param1, param2);
		}
		case (MenuAction_Cancel):
		{
			switch (param2)
			{
				case (MenuCancel_Interrupted):
				{}
				default:
				{
					PrintToChatAll("MenuAction_Cancel: %N -> %d", param1, param2);
				}
			}
		}
	}
}

/*
enum
{
	MenuCancel_Disconnected = -1,   < Client dropped from the server /
	MenuCancel_Interrupted = -2,    < Client was interrupted with another menu /
	MenuCancel_Exit = -3,           < Client exited via "exit" /
	MenuCancel_NoDisplay = -4,      < Menu could not be displayed to the client /
	MenuCancel_Timeout = -5,        < Menu timed out /
	MenuCancel_ExitBack = -6        < Client selected "exit back" on a paginated menu /
};
*/
