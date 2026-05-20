classdef PageBatchTask < handle
    %TASKMANAGER Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Name (1,1) string = ""
        Status (1,1) string = ""
        hasValidOutput (1,1) logical = false;
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
            cleanupObj = onCleanup(@() obj.cleanUp());
        
            obj.reset();
        
            obj.runWithRetry(@() obj.submitBatch(), "submitBatch");
            obj.runWithRetry(@() obj.waitBatch(), "waitBatch");
            obj.runWithRetry(@() obj.collectBatchOutput(), "collectBatchOutput");
        
            obj.retryBatch();
        end
        
        function generateUserRequest(obj)
            userReqest = preprocessing.page.buildPageRequest(obj.Pages,obj.Name);
            obj.addUserRequest(userReqest);
        end

        function addUserRequest(obj,userRequest)
            arguments
                obj (1,1) preprocessing.page.PageBatchTask
                userRequest (1,:) struct {mustBeValidUserRequest}
            end
            reqNum = numel(userRequest);
            customIds = strings(1,reqNum);
            userPrompts = strings(1,reqNum);
            
            for i = 1:numel(userRequest)
                customIds(i) = string(userRequest(i).id);
                userPrompts(i) = string(userRequest(i).userPrompt);
            end

            obj.CustomIds = customIds;
            obj.UserPrompts = userPrompts;
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

        function varargout = runWithRetry(obj,fcn,fcnName,maxRetries,baseDelay)
            arguments
                obj (1,1) preprocessing.page.PageBatchTask
                fcn (1,1) function_handle
                fcnName (1,1) string
                maxRetries (1,1) {mustBeInteger,mustBeNonnegative} = 3
                baseDelay (1,1) double {mustBePositive} = 2
            end
        
            for i = 1:(maxRetries + 1)
                try
                    if nargout == 0
                        fcn();
                    else
                        [varargout{1:nargout}] = fcn();
                    end
                    return
        
                catch ME
                    if i > maxRetries || ~obj.isRetryError(ME)
                        err = MException( ...
                            "PageBatchTask:RunFailed", ...
                            "Stage '%s' failed", ...
                            fcnName);
        
                        err = addCause(err,ME);
                        throw(err);
                    end
        
                    delay = baseDelay * 2^(i - 1);
        
                    warning("PageBatchTask:RetryStage", ...
                        "Stage '%s' failed at attempt %d/%d. \n%s", ...
                        fcnName,i,maxRetries + 1,ME.message);
        
                    pause(delay);
                end
            end
        end

        function tf = isRetryError(~, ME)
            retryIds = [ ...
                "OpenaiBatch:UpRequestFailed", ...
                "OpenaiBatch:UploadHttpError", ...
                "OpenaiBatch:GetBatchIdFailed", ...
                "OpenaiBatch:getBatchIdHttpError", ...
                "OpenaiBatch:GetBatchInfoFailed", ...
                "OpenaiBatch:GetBatchInfoHttpError", ...
                "OpenaiBatch:GetOutputFailed", ...
                "OpenaiBatch:GetOutputHttpError", ...
                "OpenaiBatch:NoOutputFile" ...
            ];
        
            tf = any(strcmp(string(ME.identifier), retryIds));
        end

        function retryCustomId = checkCompleteness(obj)
            contents = obj.Contents;
            if isempty(contents)
                retryCustomId = obj.CustomIds;
                obj.hasValidOutput = false;
                return
            end
            
            existingId = [contents.custom_id];
            notFinishedId = [contents([contents.not_finished]).custom_id];
            retryCustomId = [notFinishedId setdiff(obj.CustomIds,existingId)];

            obj.hasValidOutput = isempty(retryCustomId) && (numel(obj.CustomIds) == numel(contents));
        end

        function retryBatch(obj,maxRetries)
            arguments
                obj (1,1) preprocessing.page.PageBatchTask
                maxRetries (1,1) {mustBeInteger,mustBePositive} = 3
            end

            for i=1:maxRetries
                contents = obj.Contents;
                retryCustomId = obj.checkCompleteness();
                if obj.hasValidOutput
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

                retryJob = obj.runWithRetry(@() obj.BatchClient.submitBatch( ...
                    retryCustomId, ...
                    inputPath, ...
                    retryUser, ...
                    Developer=obj.SystemPrompt, ...
                    ModelName=obj.ModelName, ...
                    ResponseFormat=obj.ResponseFormat, ...
                    MaxCompletionTokens=obj.MaxCompletionTokens), ...
                    "retry.submitBatch");
                
                retryCleanup = onCleanup(@() obj.BatchClient.cleanupBatchJob(retryJob));
                
                retryJob = obj.runWithRetry(@() obj.BatchClient.waitBatch(retryJob), ...
                    "retry.waitBatch");
                
                [retryContents,retryMessages,retryBatchLines] = obj.runWithRetry( ...
                    @() obj.BatchClient.collectJobOutput(retryJob), ...
                    "retry.collectBatchOutput");
            
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

        function cleanUp(obj)
            if isempty(obj)
                return
            end
            
            if isempty(obj.BatchClient) || isempty(obj.BatchJob)
                return
            end
            try
                obj.BatchClient.cleanupBatchJob(obj.BatchJob);
            catch cleanupErr
                warning("PageBatchTask:CleanUpFailed","Batch cleanup failed: %s", cleanupErr.message);
            end
        end

        function reset(obj)
            obj.Status = "created";
            obj.hasValidOutput = false;
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

function mustBeValidUserRequest(userRequest)
    if ~isstruct(userRequest)
        error("preprocessing:InvalidUserRequest", ...
            "userRequest must be a struct array.");
    end

    requiredFields = ["id", "userPrompt"];
    missingFields = setdiff(requiredFields, string(fieldnames(userRequest)));

    if ~isempty(missingFields)
        error("preprocessing:InvalidUserRequest", ...
            "Missing field(s): %s.", strjoin(missingFields, ", "));
    end

    ids = strings(1, numel(userRequest));

    for i = 1:numel(userRequest)
        mustBeTextScalar(userRequest(i).id);
        mustBeTextScalar(userRequest(i).userPrompt);
        ids(i) = string(userRequest(i).id);
    end

    if any(strlength(strtrim(ids)) == 0)
        error("preprocessing:InvalidUserRequest", ...
            "Request ids must be non-empty.");
    end

    if numel(unique(ids)) ~= numel(ids)
        error("preprocessing:InvalidUserRequest", ...
            "Request ids must be unique.");
    end
end

