classdef PageBatchTask < handle
    %TASKMANAGER Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Name (1,1) string = ""
        Status (1,1) string = ""
        ValidOutput (1,1) logical = false;
        BatchJob openai.BatchJob = openai.BatchJob.empty
        Contents (1,:) struct
        Messages (1,:) struct
        BatchLines (1,:) struct
        Pages (1,:) struct = struct()
        InputPath (1,1) string = ""
        
        CustomIds (1,:) string = strings(1,0)
        ModelName (1,1) string = "gpt-5-mini"
        SystemPrompt (1,1) string = ""
        UserPrompts (1,:) string = strings(1,0)
        ResponseFormat (1,1) {openai.mustBeValidResponseFormat} = "text"
        MaxCompletionTokens (1,1) {mustBeInteger,mustBePositive} = 2000
        BatchClient openai.OpenaiBatch = openai.OpenaiBatch.empty
        
    end
    
    methods
        function obj = PageBatchTask(pages,batchClient,inputPath,taskConfig)
            arguments
                pages (1,:) struct
                batchClient openai.OpenaiBatch
                inputPath (1,1) string
                taskConfig (1,1) struct = struct()
            end
            
            [~,name] = fileparts(inputPath);
            obj.Name = name;
            
            obj.Status = "created";
            obj.BatchClient = batchClient;

            keepField = ["index" "markdown" "tables"];
            fieldNames = string(fieldnames(pages));
            pages = rmfield(pages,setdiff(fieldNames,keepField));
            obj.Pages = pages;
            

            obj.InputPath = inputPath;

            if isfield(taskConfig,"ModelName")
                obj.ModelName = taskConfig.ModelName;
            end

            if isfield(taskConfig,"PromptPath")
                obj.SystemPrompt = fileread(taskConfig.PromptPath);
            end

            if isfield(taskConfig,"ResponseFormat")
                obj.ResponseFormat = taskConfig.ResponseFormat;
            end

            if isfield(taskConfig,"MaxCompletionTokens")
                obj.MaxCompletionTokens = taskConfig.MaxCompletionTokens;
            end
        end

        function run(obj)
            obj.submitBatch();
            obj.waitBatch();
            obj.collectBatchOutput();
            obj.retryBatch();
        end
        
        function generateUserRequest(obj)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            userReq = preprocessing.classification.buildPageRequest(obj.Pages,obj.Name);
            obj.CustomIds = userReq.id;
            obj.UserPrompts = userReq.userPrompt;
        end

        function submitBatch(obj)
            if isempty(obj.CustomIds) || isempty(obj.UserPrompts)
                obj.generateUserRequest();
            end
            obj.BatchJob = obj.BatchClient.submitBatch( ...
                obj.CustomIds, ...
                obj.InputPath, ...
                obj.UserPrompts, ...
                Developer=obj.SystemPrompt, ...
                ModelName=obj.ModelName, ...
                ResponseFormat=obj.ResponseFormat, ...
                MaxCompletionTokens=obj.MaxCompletionTokens);

            obj.updateStatus();
        end
        
        function waitBatch(obj)
            obj.BatchJob = obj.BatchClient.waitBatch(obj.BatchJob);
            obj.updateStatus();
        end

        function collectBatchOutput(obj)
            obj.updateStatus();
            [obj.Contents,obj.Messages,obj.BatchLines] = obj.BatchClient.collectJobOutput(obj.BatchJob);
            obj.checkCompleteness();
        end

        function retryCustomId = checkCompleteness(obj)
            contents = obj.Contents;
            if isempty(contents)
                retryCustomId = obj.CustomIds;
                obj.ValidOutput = false;
                return
            end
            
            existingId = [contents.custom_id];
            notFinishedId = [contents([contents.not_finished]).custom_id];
            retryCustomId = [notFinishedId setdiff(obj.CustomIds,existingId)];

            obj.ValidOutput = isempty(retryCustomId) && (numel(obj.CustomIds) == numel(contents));
        end

        function retryBatch(obj,maxRetries)
            arguments
                obj (1,1) preprocessing.classification.PageBatchTask
                maxRetries (1,1) {mustBeInteger,mustBePositive} = 3
            end

            for i=1:maxRetries
                contents = obj.Contents;
                retryCustomId = obj.checkCompleteness();
                if obj.ValidOutput
                    return
                end
        
                retryNum = numel(retryCustomId);
                retryUser = strings(1,retryNum);
        
                for j = 1:numel(retryCustomId)
                    idx = find(strcmp(obj.CustomIds, retryCustomId(j)),1);
                    retryUser(j) = obj.UserPrompts(idx);
                end
        
                if ~isempty(contents) && isfield(contents,"finish_reason") && any(strcmp([contents.finish_reason],"length"))
                    obj.MaxCompletionTokens = obj.MaxCompletionTokens + 500*i;
                end
                
                inputPath = fullfile(fileparts(obj.InputPath),obj.Name + "_retry" + string(i) + ".jsonl");

                [retryContents,retryMessages,retryBatchLines] = obj.BatchClient.runBatch( ...
                    retryCustomId, ...
                    inputPath, ...
                    retryUser, ...
                    Developer=obj.SystemPrompt, ...
                    ModelName=obj.ModelName, ...
                    ResponseFormat=obj.ResponseFormat, ...
                    MaxCompletionTokens=obj.MaxCompletionTokens);
            
                for j =1:numel(retryContents)
                    customId = retryContents(j).custom_id;

                        if isempty(obj.Contents)
                            idx = [];
                        else
                            idx = find([obj.Contents.custom_id] == customId, 1);
                        end
                    
                    if isempty(idx)
                        obj.Contents(end+1) = retryContents(j);
                        obj.Messages(end+1) = retryMessages(j);
                        obj.BatchLines(end+1) = retryBatchLines(j);
                    else
                        obj.Contents(idx) = retryContents(j);
                        obj.Messages(idx) = retryMessages(j);
                        obj.BatchLines(idx) = retryBatchLines(j);
                    end
                end
            end
            obj.checkCompleteness();
        end

        function reset(obj)
            obj.Status = "created";
            obj.ValidOutput = false;
            obj.BatchJob = openai.BatchJob.empty;
            obj.Contents = struct([]);
            obj.Messages = struct([]);
            obj.BatchLines = struct([]);
        end

        function updateStatus(obj)
            if isempty(obj.BatchJob)
                obj.Status = "created";
                return
            end
            obj.Status = obj.BatchJob.Status;
        end

    end
end

