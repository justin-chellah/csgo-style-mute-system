#include <sourcemod>
#include <sdktools_voice>
#include <userinfoproxy>

#define REQUIRE_PLUGIN
#include <chat-processor>

#define REQUIRE_EXTENSIONS
#include <dhooks>

#define CHAT_TAG		"[MUTE] " 
#define GAMEDATA_FILE	"csgo_style_mute_system"

ArrayList g_hMutedPlayerSteamAccount[32+1];
DynamicHook g_hDHook_CMultiplayRules_ClientDisconnected = null;

void MutePlayer( int iReceiver, int iSender, bool bNotify = true )
{
	g_hMutedPlayerSteamAccount[iReceiver].Push( GetSteamAccountID( iSender ) );

	SetListenOverride( iReceiver, iSender, Listen_No );

	int fFlags = USERINFOFLAG_SANITIZE_NAME | USERINFOFLAG_HIDE_AVATAR | USERINFOFLAG_QUERY_FORWARD;
	UserInfoExt.SetOverride( iSender, fFlags, iReceiver );

	if ( bNotify )
	{
		ReplyToCommand( iReceiver, CHAT_TAG ... "Muted %N including their chat!", iSender );
	}
}

void UnmutePlayer( int iReceiver, int iSender, bool bNotify = true )
{
	int iSteamAccountID = g_hMutedPlayerSteamAccount[iReceiver].FindValue( GetSteamAccountID( iSender ) );

	if ( iSteamAccountID != -1 )
	{
		g_hMutedPlayerSteamAccount[iReceiver].Erase( iSteamAccountID );
	}

	SetListenOverride( iReceiver, iSender, Listen_Default );

	UserInfoExt.ResetOverride( iSender, iReceiver );

	if ( bNotify )
	{
		ReplyToCommand( iReceiver, CHAT_TAG ... "Unmuted %N including their chat!", iSender );
	}
}

public Action UserInfoExt_OnNameQuery( int iTarget, int iRecipient, char[] szName, int nMaxLength )
{
	FormatEx( szName, nMaxLength, "Muted Player #%d", GetClientUserId( iTarget ) );

	return Plugin_Changed;
}

void HandlePlayerMuteOrUnmuteByMenu( Menu hMenu, int iClient, int nItemRef, bool bIsMute )
{
	char szClientEntRef[32];
	hMenu.GetItem( nItemRef, szClientEntRef, sizeof( szClientEntRef ) );

	int iTarget = EntRefToEntIndex( StringToInt( szClientEntRef ) );

	if ( iTarget == INVALID_ENT_REFERENCE )
	{
		PrintToChat( iClient, CHAT_TAG ... "Player is no longer available." );

		if ( bIsMute )
		{
			DisplayMuteMenu( iClient );
		}
		else
		{
			DisplayUnmuteMenu( iClient );
		}

		return;
	}

	if ( bIsMute )
	{
		if ( IsSteamAccountMarkedAsMuted( iClient, iTarget ) )
		{
			PrintToChat( iClient, CHAT_TAG ... "%N is already muted.", iTarget );
		}
		else
		{
			MutePlayer( iClient, iTarget );

			DisplayMuteMenu( iClient );
		}
	}
	else if ( IsSteamAccountMarkedAsMuted( iClient, iTarget ) )
	{
		UnmutePlayer( iClient, iTarget );

		DisplayUnmuteMenu( iClient );
	}
	else
	{
		PrintToChat( iClient, CHAT_TAG ... "%N is already unmuted.", iTarget );
	}
}

public int MenuHandler_Mute( Menu hMenu, MenuAction eAction, int iClient, int nItemRef )
{
	if ( eAction == MenuAction_Select )
	{
		HandlePlayerMuteOrUnmuteByMenu( hMenu, iClient, nItemRef, true );
	}
	else if ( eAction == MenuAction_End )
	{
		delete hMenu;
	}

	return 0;
}

public int MenuHandler_Unmute( Menu hMenu, MenuAction eAction, int iClient, int nItemRef )
{
	if ( eAction == MenuAction_Select )
	{
		HandlePlayerMuteOrUnmuteByMenu( hMenu, iClient, nItemRef, false );
	}
	else if ( eAction == MenuAction_End )
	{
		delete hMenu;
	}

	return 0;
}

bool DisplayMuteMenu( int iClient )
{
	Menu hMenu = new Menu( MenuHandler_Mute );

	hMenu.SetTitle( "Select player to mute:" );
	hMenu.ExitBackButton = true;

	char szPlayerName[32];
	char szClientEntRef[32];

	for ( int iTarget = 1; iTarget <= MaxClients; iTarget++ )
	{
		if ( iTarget == iClient
			|| !IsClientConnected( iTarget )
			|| IsFakeClient( iTarget )
			|| !IsClientAuthorized( iTarget ) )
		{
			continue;
		}

		if ( IsSteamAccountMarkedAsMuted( iClient, iTarget ) )
		{
			continue;
		}

		GetClientName( iTarget, szPlayerName, sizeof( szPlayerName ) );

		IntToString( EntIndexToEntRef( iTarget ), szClientEntRef, sizeof( szClientEntRef ) );

		hMenu.AddItem( szClientEntRef, szPlayerName );
	}

	return hMenu.Display( iClient, MENU_TIME_FOREVER );
}

bool DisplayUnmuteMenu( int iClient )
{
	Menu hMenu = new Menu( MenuHandler_Unmute );

	hMenu.SetTitle( "Select player to unmute:" );
	hMenu.ExitBackButton = true;

	char szPlayerName[32];
	char szClientEntRef[32];

	for ( int iTarget = 1; iTarget <= MaxClients; iTarget++ )
	{
		if ( iTarget == iClient
			|| !IsClientConnected( iTarget )
			|| IsFakeClient( iTarget )
			|| !IsClientAuthorized( iTarget ) )
		{
			continue;
		}

		if ( !IsSteamAccountMarkedAsMuted( iClient, iTarget ) )
		{
			continue;
		}

		GetClientName( iTarget, szPlayerName, sizeof( szPlayerName ) );

		IntToString( EntIndexToEntRef( iTarget ), szClientEntRef, sizeof( szClientEntRef ) );

		hMenu.AddItem( szClientEntRef, szPlayerName );
	}

	return hMenu.Display( iClient, MENU_TIME_FOREVER );
}

public Action Command_SelfMute( int iClient, int nArgs )
{
	if ( nArgs < 1 )
	{
		if ( !DisplayMuteMenu( iClient ) )
		{
			ReplyToCommand( iClient, CHAT_TAG ... "There are no players to mute." );
		}

		return Plugin_Handled;
	}

	char szTargetName[MAX_TARGET_LENGTH];
	int[] targetList = new int[MaxClients];
	int nTargets;
	bool tn_is_ml;

	char szArgTarget[32];
	GetCmdArg( 1, szArgTarget, sizeof( szArgTarget ) );

	if ( ( nTargets = ProcessTargetString(
			szArgTarget,
			iClient,
			targetList,
			MaxClients,
			COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY | COMMAND_FILTER_CONNECTED,
			szTargetName,
			sizeof( szTargetName ),
			tn_is_ml ) ) <= 0 )
	{
		ReplyToTargetError( iClient, nTargets );

		return Plugin_Handled;
	}

	int iLastTarget = INVALID_ENT_REFERENCE;
	int nMuted = 0;

	for ( int iTarget = 0; iTarget < nTargets; iTarget++ )
	{
		if ( iClient == targetList[iTarget]
			|| !IsClientAuthorized( targetList[iTarget] )
			|| IsSteamAccountMarkedAsMuted( iClient, targetList[iTarget] ) )
		{
			continue;
		}

		nMuted++;

		iLastTarget = iTarget;

		MutePlayer( iClient, targetList[iTarget], false );
	}

	if ( !nMuted )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "There are no players to mute." );
	}
	else if ( nMuted > 1 )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "Muted %d players including their chats!", nMuted );
	}
	else if ( targetList[iLastTarget] != INVALID_ENT_REFERENCE )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "Muted %N including their chat!", targetList[iLastTarget] );
	}

	return Plugin_Handled;
}

public Action Command_SelfUnmute( int iClient, int nArgs )
{
	if ( nArgs < 1 )
	{
		if ( !DisplayUnmuteMenu( iClient ) )
		{
			ReplyToCommand( iClient, CHAT_TAG ... "You've nobody muted." );
		}

		return Plugin_Handled;
	}

	char szTargetName[MAX_TARGET_LENGTH];
	int[] targetList = new int[MaxClients];
	int nTargets;
	bool tn_is_ml;

	char szArgTarget[32];
	GetCmdArg( 1, szArgTarget, sizeof( szArgTarget ) );

	if ( ( nTargets = ProcessTargetString(
			szArgTarget,
			iClient,
			targetList,
			MaxClients,
			COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY | COMMAND_FILTER_CONNECTED,
			szTargetName,
			sizeof( szTargetName ),
			tn_is_ml ) ) <= 0 )
	{
		ReplyToTargetError( iClient, nTargets );

		return Plugin_Handled;
	}

	int iLastTarget = INVALID_ENT_REFERENCE;
	int nUnmuted = 0;

	for ( int iTarget = 0; iTarget < nTargets; iTarget++ )
	{
		if ( iClient == targetList[iTarget]
			|| !IsClientAuthorized( targetList[iTarget] )
			|| !IsSteamAccountMarkedAsMuted( iClient, targetList[iTarget] ) )
		{
			continue;
		}

		nUnmuted++;

		iLastTarget = iTarget;

		UnmutePlayer( iClient, targetList[iTarget], false );
	}

	if ( !nUnmuted )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "You've nobody muted." );
	}
	else if ( nUnmuted > 1 )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "Unmuted %d players including their chats!", nUnmuted );
	}
	else if ( targetList[iLastTarget] != INVALID_ENT_REFERENCE )
	{
		ReplyToCommand( iClient, CHAT_TAG ... "Unmuted %N including their chat!", targetList[iLastTarget] );
	}

	return Plugin_Handled;
}

bool IsSteamAccountMarkedAsMuted( int iReceiver, int iSender )
{
	int iSteamAccountID = g_hMutedPlayerSteamAccount[iReceiver].FindValue( GetSteamAccountID( iSender ) );

	if ( iSteamAccountID == -1 )
	{
		return false;
	}

	return true;
}

public void OnClientAuthorized( int iClient, const char[] szAuth )
{
	if ( IsFakeClient( iClient ) )
	{
		return;
	}

	for ( int iTarget = 1; iTarget <= MaxClients; iTarget++ )
	{
		if ( iTarget == iClient
			|| !IsClientConnected( iTarget )
			|| IsFakeClient( iTarget )
			|| !IsClientAuthorized( iTarget ) )
		{
			continue;
		}

		if ( IsSteamAccountMarkedAsMuted( iTarget, iClient ) )
		{
			MutePlayer( iTarget, iClient, false );
		}

		if ( IsSteamAccountMarkedAsMuted( iClient, iTarget ) )
		{
			MutePlayer( iClient, iTarget, false );
		}
	}
}

public Action CP_OnChatMessageSendPre( int iSender, int iReciever, char[] szBuffer, int nMaxLength )
{
	if ( IsSteamAccountMarkedAsMuted( iReciever, iSender ) )
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

// Cleanups should never occur on the player_disconnect event. It's not reliable/doesn't always fire,
// not to mention game SDK does it the same way
public MRESReturn DHook_CMultiplayRules_ClientDisconnected( Address addrThis, DHookParam hParams )
{
	int iClient = hParams.Get( 1 );

	if ( IsFakeClient( iClient ) )
	{
		return MRES_Ignored;
	}

	g_hMutedPlayerSteamAccount[iClient].Clear();

	return MRES_Ignored;
}

public void OnMapStart()
{
	g_hDHook_CMultiplayRules_ClientDisconnected.HookGamerules( Hook_Post, DHook_CMultiplayRules_ClientDisconnected );
}

public void OnPluginEnd()
{
	for ( int iClient = 1; iClient <= MaxClients; iClient++ )
	{
		if ( !IsClientConnected( iClient ) )
		{
			continue;
		}

		for ( int iTarget = 1; iTarget <= MaxClients; iTarget++ )
		{
			if ( !IsClientConnected( iTarget ) )
			{
				continue;
			}

			SetListenOverride( iClient, iTarget, Listen_Default );
		}
	}
}

public void OnPluginStart()
{
	GameData hGameData = new GameData( GAMEDATA_FILE );

	if ( hGameData == null )
	{
		SetFailState( "Unable to load gamedata file \"" ... GAMEDATA_FILE ... "\"" );
	}

	int iVtbl_CMultiplayRules_ClientDisconnected = hGameData.GetOffset( "CMultiplayRules::ClientDisconnected" );
	
	if ( iVtbl_CMultiplayRules_ClientDisconnected == -1 )
	{
		delete hGameData;
		
		SetFailState( "Unable to find gamedata offset entry for \"CMultiplayRules::ClientDisconnected\"" );
	}

	g_hDHook_CMultiplayRules_ClientDisconnected = new DynamicHook( iVtbl_CMultiplayRules_ClientDisconnected, HookType_GameRules, ReturnType_Void, ThisPointer_Address );
	g_hDHook_CMultiplayRules_ClientDisconnected.AddParam( HookParamType_Edict );

	LoadTranslations( "common.phrases" );

	RegConsoleCmd( "sm_selfmute", Command_SelfMute, "Voice and chat-mute players" );
	RegConsoleCmd( "sm_sm", Command_SelfMute, "Voice and chat-mute players" );

	RegConsoleCmd( "sm_su", Command_SelfUnmute, "Voice and chat-unmute players" );
	RegConsoleCmd( "sm_selfunmute", Command_SelfUnmute, "Voice and chat-unmute players" );

	for ( int iEntry = 1; iEntry < sizeof( g_hMutedPlayerSteamAccount ); iEntry++ )
	{
		g_hMutedPlayerSteamAccount[iEntry] = new ArrayList( 1 );
	}
}

public Plugin myinfo =
{
	name = "[ANY] CS:GO-Style Mute System",
	author = "Justin \"Sir Jay\" Chellah",
	description = "Allows players to mute and unmute other players in the same fashion as CS: GO by sanitizing player names and hiding avatars",
	version = "1.0.0",
	url = "https://justin-chellah.com"
};