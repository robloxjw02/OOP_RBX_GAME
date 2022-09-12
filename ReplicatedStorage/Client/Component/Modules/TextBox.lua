local TextBoxModule = {}
TextBoxModule.__index = TextBoxModule

local UserInputService = game:GetService('UserInputService')
local TextService = game:GetService('TextService')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Fusion = require(ReplicatedStorage.Fusion)
local New = Fusion.New
local Children = Fusion.Children

function TextBoxModule.new(Properties)
	local self = setmetatable({}, TextBoxModule)
	
	self.Inputs = {}
	self.Ignores = {}
	self.Waypoints = {}
	
	self.LastTextChange = tick()
	self.LastSnapshot		= tick()
	self.LastText			= ''
	
	self.HistoryController = {
		UndoStack = {},
		RedoStack = {}
	}
	
	self.Properties = Properties or {}
	
	if self.Properties.Parent == nil then
		warn('[Textbox] You need to direct a parent')
		return
	end
	
	if not (self.Properties.Parent and typeof(self.Properties.Parent)== 'Instance' and self.Properties.Parent:IsA("GuiObject")) then
		warn('[Textbox] Invalid parent')
		return
	end
	
	print(self.Properties)
	local TextSize = self.Properties.TextSize or 16
	local TextWrapped			= (self.Properties.TextWrapped == nil and true)	or self.Properties.TextWrapped
	local MultiLine			= (self.Properties.Multiline == nil and true)	or self.Properties.Multiline
	local Padded				= (self.Properties.Padded == nil and true)				or self.Properties.Padded
	local ClearTextOnFocus		= (self.Properties.ClearTextOnFocus == nil and false)	or self.Properties.ClearTextOnFocus
	
	local TextColor3 = self.Properties.TextColor3 or Color3.new(1, 1, 1)
	local TextFont = self.Properties.Font or Enum.Font.SourceSans
	local TextXAlignment = self.Properties.TextXAlignment or Enum.TextXAlignment.Left
	local TextYAlignment = self.Properties.TextYAlignment or Enum.TextYAlignment.Top
	local PlaceholderText = self.Properties.PlaceholderText or ''
	local PlaceholderColor3 = self.Properties.PlaceholderColor3 or Color3.new(0.1, 0.1, 0.1)
	
	local Scroller = New 'ScrollingFrame' {
		Name = 'TextFrame',
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		ScrollBarImageColor3 = Color3.fromRGB(117, 117, 117),
		ScrollBarThickness = TextSize * 0.5,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		CanvasSize = UDim2.new(),
		Parent = self.Properties.Parent,
		
		[Children] = {
			New 'TextBox' {
				Name = 'Input',
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -TextSize, 1, -TextSize),
				Position = UDim2.new(0, TextSize * 0.5, 0, TextSize * 0.5),
				MultiLine = MultiLine,
				TextWrapped = TextWrapped,
				ClearTextOnFocus = ClearTextOnFocus,
				TextSize = TextSize,
				Text = '',
				Font = TextFont,
				TextColor3 = TextColor3,
				PlaceholderText = PlaceholderText,
				PlaceholderColor3 = PlaceholderColor3,
				TextXAlignment = TextXAlignment,
				TextYAlignment = TextYAlignment
			}
		}
	}
	
	Scroller.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Scroller.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	
	local Input = Scroller.Input
	Input:GetPropertyChangedSignal('Text'):Connect(function()
		self.LastTextChange = tick()

		local TextBounds = TextService:GetTextSize(Input.Text,Input.TextSize,Input.Font, Vector2.new(TextWrapped and Scroller.AbsoluteWindowSize.X or 99999,99999))
		Scroller.CanvasSize = UDim2.new(
			0,TextBounds.X,
			0,TextBounds.Y+(Padded and Scroller.AbsoluteWindowSize.Y - TextSize or 0)
		)
	end)
	
	self.Instance = Input
	
	function self.Write(Text, Start, End)
		Input.Text = string.sub(Input.Text,1,Start).. Text .. string.sub(Input.Text,End+1)
	end

	function self.SetContent(Text)
		Input.Text = Text
		self:Clear()
	end
	
	local TextPlus = {
		self:Clear(),
		self:Redo(),
		self:TakeSnapshot(),
		self:Undo(),
		self.Write,
		self.SetContent
	}
	
	self.Inputs[Input] = TextPlus
	self.Waypoints[Input] = self.HistoryController
	
	--Have the first snap be the blank GUI
	self:TakeSnapshot()

	RunService.Heartbeat:Connect(function()
		if self.LastText == Input.Text then
			return
		end

		if self.Ignores[Input] then
			self.Ignores[Input] = nil
			self.LastText = Input.Text
			return
		end

		if (tick() - self.LastTextChange > 0.5) or (tick() - self.LastSnapshot > 2) or (math.abs(#self.LastText -#Input.Text) > 10) then
			self:TakeSnapshot()
			self.LastSnapshot = tick()
			self.LastText = Input.Text
		end
	end)
	
	UserInputService.InputBegan:Connect(function(Inputs, GameProcessed)
		if not GameProcessed then 
			return
		end

		local IsFocused = self.Instance:IsFocused()
		
		if IsFocused then
			print(IsFocused)
			task.wait()
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				-- Handle shortcuts

				if Inputs.KeyCode == Enum.KeyCode.D then
					-- Select current word
					local _,w2 = string.find(string.sub(self.Instance.Text, Input.CursorPosition), "^%w+")
					local w3 = string.find(string.sub(self.Instance.Text, 1, Input.CursorPosition), "%w+$")
					print(w2)
					print(w3)

					if w2 and w3 then
						self.Instance.SelectionStart = w3
						self.Instance.CursorPosition = w2+ Input.CursorPosition
					end
				elseif Inputs.KeyCode == Enum.KeyCode.Z then
					-- Undo
					self:Undo()

				elseif Inputs.KeyCode == Enum.KeyCode.Y then
					-- Redo
					self:Redo()
				elseif Inputs.KeyCode == Enum.KeyCode.Backspace then
					self:Delete()
				elseif Inputs.KeyCode == Enum.KeyCode.T then
					local newString = string.rep(' ', 3)
					self.Instance.Text = self.Instance.Text..newString
					self.Instance.CursorPosition = #self.Instance.Text + 1
				elseif Inputs.KeyCode == Enum.KeyCode.N then
					local _,w2 = string.find(string.sub(self.Instance.Text, Input.CursorPosition), "^%w+")
					
					local newString = '\n\n'
					self.Instance.Text = self.Instance.Text..newString
					self.Instance.CursorPosition = #self.Instance.Text + 1
				end
			end
		end
	end)
	
	return self
end

function TextBoxModule:Clear()
	self.HistoryController.UndoStack = {}
	self.HistoryController.RedoStack = {}
end

function TextBoxModule:TakeSnapshot()

	self.HistoryController.UndoStack[#self.HistoryController.UndoStack+1] = {
		Text			= self.Instance.Text;
		CursorPosition	= self.Instance.CursorPosition;
		SelectionStart	= self.Instance.SelectionStart;
	};

	-- Clear redo
	if #self.HistoryController.RedoStack > 0 then
		self.HistoryController.RedoStack = {}
	end

	-- Limit undo size
	while #self.HistoryController.UndoStack > 30 do -- max of 30 snapshots (except for ones that come back from the redo stack)
		table.remove(self.HistoryController.UndoStack,1)
	end
end

function TextBoxModule:Undo()
	if #self.HistoryController.UndoStack > 1 then
		self.Ignores[self.Instance] = true

		local Waypoint = self.HistoryController.UndoStack[#self.HistoryController.UndoStack - 1]
		for Prop, Value in pairs(Waypoint) do
			self.Instance[Prop] = Value
		end

		self.HistoryController.RedoStack[#self.HistoryController.RedoStack + 1] = self.HistoryController.UndoStack[#self.HistoryController.UndoStack]
		self.HistoryController.UndoStack[#self.HistoryController.UndoStack] = nil
	end
end

function TextBoxModule:Redo()
	if #self.HistoryController.RedoStack > 0 then

		--print("Redo")
		self.Ignores[self.Instance] = true
		
		local Waypoint = self.HistoryController.RedoStack[#self.HistoryController.RedoStack]
		for Prop, Value in pairs(Waypoint) do
			self.Instance[Prop] = Value
		end

		self.HistoryController.UndoStack[#self.HistoryController.UndoStack + 1] = Waypoint
		self.HistoryController.RedoStack[#self.HistoryController.RedoStack] = nil
	end
end

function TextBoxModule:Delete()
	self.Instance.Text = ''
	self:Clear()
end

return TextBoxModule