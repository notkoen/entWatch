#if defined entWatch_class_item_trigger_included
	#endinput
#endif

#define entWatch_class_item_trigger_included

methodmap CItemTrigger < StringMap
{
	public CItemTrigger(CConfigTrigger hConfigTrigger = null, CItem hItem = null)
	{
		StringMap stringMap = new StringMap();

		stringMap.SetValue("hConfigTrigger",    hConfigTrigger);
		stringMap.SetValue("hItem",             hItem);

		stringMap.SetValue("iTrigger",          INVALID_ENT_REFERENCE);
		stringMap.SetValue("iState",            EW_ENTITY_STATE_INITIAL);

		return view_as<CItemTrigger>(stringMap);
	}

	property CConfigTrigger hConfigTrigger
	{
		public get()
		{
			CConfigTrigger hValue;
			if (this.GetValue("hConfigTrigger", hValue))
				return hValue;

			return null;
		}
		public set(CConfigTrigger hValue)
		{
			this.SetValue("hConfigTrigger", hValue);
		}
	}

	property CItem hItem
	{
		public get()
		{
			CItem hValue;
			if (this.GetValue("hItem", hValue))
				return hValue;

			return null;
		}
		public set(CItem hValue)
		{
			this.SetValue("hItem", hValue);
		}
	}

	property int iTrigger
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iTrigger", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iTrigger", iValue);
		}
	}

	property int iState
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iState", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iState", iValue);
		}
	}
}
