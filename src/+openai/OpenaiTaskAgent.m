classdef OpenaiTaskAgent < handle
    %UNTITLED4 Summary of this class goes here
    %   Detailed explanation goes here
    properties
        ModelName (1,1) string
        SystemPrompt (1,1) string
        ResponseFormat {openai.mustBeValidResponseFormat}
        Tools openAIFunction = openAIFunction.empty
        GenerateTimeOut (1,1) double {mustBePositive, mustBeFinite}
    end

    properties(Access = private)
        ApiKey (1,1) string
    end
    
    properties(SetAccess = private)
        Chat openAIChat
        Messages openAIMessages
        TokenConsumption (1,1) double 
    end

    methods
        function obj = OpenaiTaskAgent(apiKey,generateTimeOut,taskConfig)
            %UNTITLED4 Construct an instance of this class
            %   Detailed explanation goes here
            arguments
                apiKey (1,1) string
                generateTimeOut (1,1) double {mustBePositive, mustBeFinite} = 3000
                taskConfig.ModelName (1,1) string = "gpt-5-mini"
                taskConfig.PromptPath (1,1) string = ""
                taskConfig.ResponseFormat{openai.mustBeValidResponseFormat} = "text"
                taskConfig.Tools openAIFunction = openAIFunction.empty
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
            obj.ModelName = taskConfig.ModelName;
            obj.ResponseFormat = taskConfig.ResponseFormat;
            obj.Tools = taskConfig.Tools;
            obj.GenerateTimeOut = generateTimeOut;
            
            obj.resetMessages();
            obj.resetTokenConsumption();
            
            try
                obj.Chat = openAIChat( ...
                    obj.SystemPrompt, ...
                    APIKey = obj.ApiKey, ...
                    ModelName = obj.ModelName,...
                    ResponseFormat = obj.ResponseFormat, ...
                    Tools = obj.Tools ...
                    );

            catch ME
                error("OpenaiTaskAgent:CreateChatError","Failed to create OpenAIChat object\n%s",ME.message);
            end
        end

        function [output,message,response] = runTask(obj,userMessage)
            arguments
                obj (1,1) OpenaiTaskAgent
                userMessage {mustBeTextScalar}
            end
            newMessages = addUserMessage(obj.Messages, string(userMessage));

            try
                [output,message,response] = generate( ...
                    obj.Chat, ...
                    newMessages, ...
                    TimeOut=obj.GenerateTimeOut ...
                    );
                newMessages = addResponseMessage(newMessages,message);
            catch ME
                error("OpenaiTaskAgent:RunTaskError","Error in generating answer: \n%s",ME.message);
            end
            
            obj.Messages = newMessages;
            obj.TokenConsumption = obj.TokenConsumption + getTotalTokens(response);

        end
        
        function resetMessages(obj)
            obj.Messages = openAIMessages;
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