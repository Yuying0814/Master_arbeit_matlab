classdef OpenaiTaskAgent < handle
    %UNTITLED4 Summary of this class goes here
    %   Detailed explanation goes here
    properties
        ModelName (1,1) string = "gpt-5-mini"
        Tools openAIFunction = openAIFunction.empty
        GenerateTimeOut (1,1) double {mustBePositive, mustBeFinite} = 3000
    end

    properties(Access = private)
        ApiKey (1,1) string = ""
    end
    
    properties(SetAccess = private)
        Chat (1,1) openAIChat
        Messages (1,1) messageHistory
        SystemPrompt (1,1) string = ""
        TaskPrompt (1,1) string = ""
        ResponseFormat (1,1) {openai.mustBeValidResponseFormat} = "text"
        TokenConsumption (1,1) double = 0
    end

    methods
        function obj = OpenaiTaskAgent(apiKey,taskPrompt,taskConfig,generateTimeOut)
            %UNTITLED4 Construct an instance of this class
            %   Detailed explanation goes here
            arguments
                apiKey (1,1) string
                taskPrompt (1,1) string
                taskConfig (1,1) struct
                generateTimeOut (1,1) double {mustBePositive, mustBeFinite} = 3000
            end
            
            if isempty(apiKey) || strlength(apiKey) == 0
                error("OpenaiTaskAgent:NoApiKey","Empty ApiKey Input");
            end

            promptPath = strtrim(string(taskConfig.PromptPath));

            if strlength(promptPath) == 0
                systemPrompt = "";
            elseif isfile(promptPath)
                systemPrompt = string(fileread(promptPath));
            else
                error("OpenaiTaskAgent:FileNotFound","Prompt not found: %s",promptPath);
            end
            obj.SystemPrompt = systemPrompt;
            
            obj.ApiKey = apiKey;
            obj.TaskPrompt = string(taskPrompt);

            if isfield(taskConfig,"ModelName")
                obj.ModelName = taskConfig.ModelName;
            end

            if isfield(taskConfig,"ResponseFormat")
                obj.ResponseFormat = taskConfig.ResponseFormat;
            end

            if isfield(taskConfig,"Tools")
                obj.Tools = taskConfig.Tools;
            end

            obj.GenerateTimeOut = generateTimeOut;
            obj.resetMessages();
            obj.resetTokenConsumption();
            
            try
                obj.Chat = openAIChat( ...
                    obj.SystemPrompt, ...
                    APIKey = obj.ApiKey, ...
                    ModelName = obj.ModelName,...
                    Tools = obj.Tools ...
                    );

            catch ME
                error("OpenaiTaskAgent:CreateChatError","Failed to create OpenAIChat object\n%s",ME.message);
            end
        end

        function [output,message,response] = runTask(obj)
            
            newMessages = addUserMessage(obj.Messages,obj.TaskPrompt);
            
            try
                [output,message,response] = generate( ...
                    obj.Chat, ...
                    newMessages, ...
                    ResponseFormat= obj.ResponseFormat, ...
                    TimeOut=obj.GenerateTimeOut ...
                    );
                newMessages = addResponseMessage(newMessages,message);
            catch ME
                error("OpenaiTaskAgent:RunTaskError","Error in generating answer: \n%s",ME.message);
            end
            
            obj.Messages = newMessages;
            obj.TokenConsumption = obj.TokenConsumption + getTotalTokens(response);
        end

        function [output,message,response] = runChat(obj,userMessage)
            newMessages = addUserMessage(obj.Messages, string(userMessage));

            try
                [output,message,response] = generate( ...
                    obj.Chat, ...
                    newMessages, ...
                    ResponseFormat = "text", ...
                    TimeOut=obj.GenerateTimeOut ...
                    );
                newMessages = addResponseMessage(newMessages,message);
            catch ME
                error("OpenaiTaskAgent:RunChatError","Error in generating answer: \n%s",ME.message);
            end
            obj.Messages = newMessages;
            obj.TokenConsumption = obj.TokenConsumption + getTotalTokens(response);
        end
        
        function resetMessages(obj)
            obj.Messages = messageHistory;
        end

        function resetTokenConsumption(obj)
            obj.TokenConsumption = 0;
        end

    end
end

%% Helper function

function totalTokens = getTotalTokens(response)
    totalTokens = 0;
    if ~isfield(response, "Body")
        return;
    end

    if ~isfield(response.Body, "Data")
        return;
    end

    data = response.Body.Data;
    if ~isfield(data, "usage")
        return;
    end
    usage = data.usage;

    if isfield(usage, "total_tokens")
        totalTokens = usage.total_tokens;
    end
end