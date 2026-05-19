classdef OpenaiBatch < handle
    %OPENAICLIENT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Access = private)
        ApiKey (1,1) string
    end

    properties
        JSONLs (1,:) string = strings(1,0)
    end
    
    methods
        function obj = OpenaiBatch(apiKey)
            %OPENAICLIENT Construct an instance of this class
            %   Detailed explanation goes here
            if isempty(apiKey) || strlength(apiKey) == 0
                error("OpenaiBatch:NoApiKey","Empty ApiKey Input");
            end
            obj.ApiKey = apiKey;
        end

        function [contents,messages,batchLines] = runBatch(obj,id,inputPath,user,opts)
            arguments
                obj (1,1) openai.OpenaiBatch
                id (1,:) string
                inputPath (1,1) string
                user (1,:) string
                
                opts.CheckInterval (1,1) double = 10
                opts.Developer (1,1) string
                opts.ModelName (1,1) string = "gpt-5-mini"
                opts.ResponseFormat (1,1) {openai.mustBeValidResponseFormat}
                opts.MaxCompletionTokens (1,1) double {mustBeInteger,mustBePositive}
                opts.Tools
            end
            
            nv = {};

            modelName = opts.ModelName;
            checkInterval = opts.CheckInterval;

            opts = rmfield(opts,["ModelName" "CheckInterval"]);
            nv = namedargs2cell(opts);

            obj.resetJSONLs();
            obj.buildBatchJSONL( ...
                modelName, ...
                id, ...
                user, ...
                nv{:});
        
            obj.writeBatchReqFile(inputPath);
        
            inputFileId = obj.uploadBatchRequest(inputPath);
            inputFileCleanup = onCleanup(@() obj.deleteUploadedFile(inputFileId));
            
            batchId = obj.getBatchId(inputFileId);

            obj.waitCompletion(batchId,checkInterval);
        
            outputFileId = obj.getOutputId(batchId);
            rawOutput = obj.getBatchOutput(outputFileId);

            [contents,messages,batchLines] = obj.parseBatchOutput(rawOutput);
        end

        function Job = submitbatch(obj,id,inputPath,user,opts)
            arguments
                obj (1,1) openai.OpenaiBatch
                id (1,:) string
                inputPath (1,1) string
                user (1,:) string
                
                opts.CheckInterval (1,1) double = 10
                opts.Developer (1,1) string
                opts.ModelName (1,1) string = "gpt-5-mini"
                opts.ResponseFormat (1,1) {openai.mustBeValidResponseFormat}
                opts.MaxCompletionTokens (1,1) double {mustBeInteger,mustBePositive}
                opts.Tools
            end
            nv = {};

            modelName = opts.ModelName;
            checkInterval = opts.CheckInterval;

            opts = rmfield(opts,["ModelName" "CheckInterval"]);
            nv = namedargs2cell(opts);

            obj.resetJSONLs();
            obj.buildBatchJSONL( ...
                modelName, ...
                id, ...
                user, ...
                nv{:});
            obj.writeBatchReqFile(inputPath);
        
            inputFileId = obj.uploadBatchRequest(inputPath);
            inputFileCleanup = onCleanup(@() obj.deleteUploadedFile(inputFileId));
            
            batchId = obj.getBatchId(inputFileId);

        end

        function buildBatchJSONL(obj,modelName,id,user,opts)
            arguments
                obj (1,1) openai.OpenaiBatch
                modelName (1,1) string
                id (1,:) string % same ids within one batch are not allowed!!! 
                user (1,:) string

                opts.Developer (1,1) string = ""
                opts.ResponseFormat (1,1) {openai.mustBeValidResponseFormat}
                opts.MaxCompletionTokens (1,1) double {mustBeInteger,mustBePositive} = 2000
                opts.Tools 
            end
            idNum = numel(id);
            userNum = numel(user);
            
            if idNum ~= userNum
                error("OpenaiBatch:InvalidUserSize","user must have the same number of elements as id.")
            end

            if numel(unique(id)) ~= idNum
                error("OpenaiBatch:DuplicateId", ...
                "id must not contain same id within one batch.");
            end
            
            for i = 1:idNum
                body = struct( ...
                "model",  modelName, ...
                "messages", [ ...
                struct("role", "developer", "content",string(opts.Developer)), ...
                struct("role", "user", "content", string(user(i))) ...
                ]);

                if isfield(opts,"ResponseFormat")
                    responseFormat = opts.ResponseFormat;
                    
                    if isstring(responseFormat) || ischar(responseFormat)
                        responseFormat = strtrim(lower(string(responseFormat)));
        
                        switch responseFormat
                            case "text"
                                schema = struct("type","text");
                            case "json"
                                schema = struct("type","json_object");
                            otherwise
                                error("OpenaiBatch:InvalidResponseFormat","Response format must be ""text"",""json""or struct.");
                        end
                        
                    elseif isstruct(responseFormat)
                        schema = utils.buildJSONSchema(responseFormat);
                    else
                        error("OpenaiBatch:InvalidResponseFormat", ...
                            "Response format must be ""text"", ""json"", or struct.");
                    end
                    
                    body.response_format = schema;
                end

                if isfield(opts,"MaxCompletionTokens")
                    body.max_completion_tokens = opts.MaxCompletionTokens;
                end

                if isfield(opts,"Tools")
                end
    
                JSONLStruct = struct( ...
                    "custom_id", id(i), ...
                    "method", "POST", ...
                    "url", "/v1/chat/completions", ...
                    "body", body ...
                    );
                JSONL= jsonencode(JSONLStruct);
                obj.JSONLs(end+1) = JSONL; 
            end
        end

        function obj = resetJSONLs(obj)
            obj.JSONLs = strings(1,0);
        end

        function writeBatchReqFile(obj,path)
            if isempty(obj.JSONLs)
                warning("OpenaiBatch:EmptyJSONLs", ...
                    "No JSONL data to write. Use buildBatchJSONL(obj,id,developer,user,taskConfig) to create a batchJSONL");
            end

            fid = fopen(path,"w","n","UTF-8");
            if fid == -1
                error("OpenaiBatch:OpenFileError","Failed to open file: %s", path);
            end
            
            cleanupObj = onCleanup(@() fclose(fid));
            for i = 1:numel(obj.JSONLs)
                try
                    fprintf(fid,'%s\n',obj.JSONLs(i));
                catch ME
                    error("OpenaiBatch:WriteError","Line %d, Failed to write to file: %s\n%s",i,path,ME.message);
                end
            end
        end
        
        function inputFileId = uploadBatchRequest(obj,batchReqFile)          
            if ~isfile(batchReqFile)
                error("OpenaiBatch:UploadFailed", ...
                    "Batch file not found: %s", batchReqFile);
            end
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.io.FileProvider
            import matlab.net.http.io.MultipartFormProvider
            import matlab.net.http.StatusCode

            destination = "https://api.openai.com/v1/files";

            provider = MultipartFormProvider(...
                "purpose", "batch", ...
                "file", FileProvider(batchReqFile));
            
            header = HeaderField("Authorization", "Bearer "+obj.ApiKey);
            request = RequestMessage(RequestMethod.POST,header,provider);
            
            try
                response = request.send(URI(destination));
            catch ME
                error("OpenaiBatch:UpRequestFailed", ...
                    "Failed to send upload request\n%s", ME.message);
            end
            
            if response.StatusCode ~= StatusCode.OK
                error("OpenaiBatch:UploadHttpError", "Upload http error: %s\n%s", ...
                    string(response.StatusCode), ...
                    jsonencode(response.Body.Data));
            end

            result = response.Body.Data;

            if ~isfield(result,"id")
                error("OpenaiBatch:InvalidResponse", "Response has no id");
            end

            inputFileId = string(result.id);
        end

        function batchId = getBatchId(obj,inputFileId)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.io.JSONProvider
            import matlab.net.http.StatusCode

            destination = "https://api.openai.com/v1/batches";

            batchBody = struct( ...
                "input_file_id",inputFileId, ...
                "endpoint","/v1/chat/completions", ...
                "completion_window","24h");
            
            headersAuth = HeaderField("Authorization", "Bearer "+obj.ApiKey);
            headersCont = HeaderField("Content-Type","application/json");
            headers = [headersAuth headersCont];
            
            provider = JSONProvider(batchBody);
            request = RequestMessage(RequestMethod.POST,headers,provider);

            try
                response = request.send(URI(destination));
            catch ME
                error("OpenaiBatch:GetBatchIdFailed", ...
                    "Failed to get batch Id\n%s", ME.message);
            end

            if response.StatusCode ~= StatusCode.OK
                error("OpenaiBatch:getBatchIdHttpError", "Get batch id http error: %s\n%s", ...
                    string(response.StatusCode), ...
                    jsonencode(response.Body.Data));
            end

            result = response.Body.Data;

            if ~isfield(result, "id")
                error("OpenaiBatch:InvalidResponse", "Response has no id");
            end

            batchId = string(result.id);
        end
        
        function batchInfo = getBatchInfo(obj, batchId)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.StatusCode
        
            destination = "https://api.openai.com/v1/batches/" + batchId;
        
            headersAuth = HeaderField("Authorization", "Bearer " + obj.ApiKey);
            request = RequestMessage(RequestMethod.GET, headersAuth);
        
            try
                response = request.send(URI(destination));
            catch ME
                error("OpenaiBatch:GetBatchInfoFailed", ...
                    "Failed to get batch information.\n%s", ME.message);
            end
        
            if response.StatusCode ~= StatusCode.OK
                error("OpenaiBatch:GetBatchInfoHttpError", ...
                    "Get batch information HTTP error: %s\n%s", ...
                    string(response.StatusCode), ...
                    jsonencode(response.Body.Data));
            end
        
            batchInfo = response.Body.Data;
        end

        function batchInfo = waitCompletion(obj,batchId,checkInterval)
            arguments
                obj (1,1) openai.OpenaiBatch
                batchId (1,1) string
                checkInterval(1,1) double {mustBePositive}
            end

            endStatus = ["completed", "failed", "cancelled", "expired"];
        
            while true
                batchInfo = obj.getBatchInfo(batchId);
                batchStatus = string(batchInfo.status);
                disp(batchId+": "+batchStatus);
        
                if any(batchStatus == endStatus)
                    break
                end
        
                pause(checkInterval);
            end
        
            if batchStatus ~= "completed"
                error("OpenaiBatch:BatchFailed", ...
                    "Batch ended with status: %s", batchStatus);
            end
        end

        function batchStatus = getBatchStatus(obj,batchId)
            batchInfo = obj.getBatchInfo(batchId);

            if ~isfield(batchInfo, "status")
                error("OpenaiBatch:InvalidResponse", "Response has no status");
            end
            
            batchStatus = string(batchInfo.status);
        end

        function outputFileId = getOutputId(obj,batchId)
            
            batchInfo = obj.getBatchInfo(batchId);
            batchStatus = string(batchInfo.status);
            
            if ~strcmpi(batchStatus,"completed")
                error("OpenaiBatch:BatchNotCompleted","Batch process not completed\n%s",batchStatus);
            end
            
            if ~isfield(batchInfo,"output_file_id")
                error("OpenaiBatch:InvalidResponse", "Response has no output file id");
            end

            outputFileId = string(batchInfo.output_file_id);
        end
        
        function output = getBatchOutput(obj,outputFileId)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.StatusCode

            destination = "https://api.openai.com/v1/files/" + outputFileId + "/content";

            headersAuth = HeaderField("Authorization", "Bearer "+ obj.ApiKey);
            request = RequestMessage(RequestMethod.GET,headersAuth);

            try
                response = request.send(URI(destination));
            catch ME
                error("OpenaiBatch:GetOutputFailed", ...
                    "Failed to get batch output\n%s", ME.message);
            end
            
            if response.StatusCode ~= StatusCode.OK
                error("OpenaiBatch:GetOutputHttpError", "Get batch output http error: %s\n%s", ...
                    string(response.StatusCode), ...
                    jsonencode(response.Body.Data));
            end

            output = response.Body.Data;
        end
        
        function [contents,messages,batchLines] = parseBatchOutput(~,rawOutput)

            jsonLines = char(rawOutput)';
            lines = preprocessing.utils.text2lines(jsonLines);
            
            contents = struct( ...
                "custom_id", {}, ...
                "finish_reason", {}, ...
                "content", {}, ...
                "not_finished", {} ...
                );

            messages = struct( ...
                    "custom_id",{},...
                    "message",{});

            batchLines = struct( ...
                "id", {},...
                "custom_id",{}, ...
                "response",{}, ...
                "error",{});
           
            
            for i = 1:numel(lines)
                try
                    batchLine = jsondecode(strtrim(string(lines{i})));
                catch
                    continue;
                end

                customId = string(batchLine.custom_id);
                finishReason = string(batchLine.response.body.choices(1).finish_reason);
                message = batchLine.response.body.choices(1).message;
                
                batchLines(end+1) = batchLine;
                messages(end+1) = struct( ...
                    "custom_id",customId, ...
                    "message",message);

                if all(~strcmp(finishReason,["stop" "tool_calls"]))
                    contents(end+1) = struct( ...
                        "custom_id",customId, ...
                        "finish_reason",finishReason, ...
                        "content","", ...
                        "not_finished",true);
                    continue
                end
                
                content = "";
        
                if isfield(message, "content") && ~isempty(message.content)
                    contentText = string(message.content);
        
                    if strlength(strtrim(contentText)) > 0
                        try
                            content = jsondecode(contentText);
                        catch
                            content = contentText;
                        end
                    end
                end

                contents(end+1) = struct( ...
                    "custom_id",customId, ...
                    "finish_reason",finishReason, ...
                    "content",content, ...
                    "not_finished",false);
            end
        end

        function deleteUploadedFile(obj,fileId)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.StatusCode

            destination = "https://api.openai.com/v1/files/" + fileId;

            headersAuth = HeaderField("Authorization", "Bearer "+ obj.ApiKey);
            request = RequestMessage(RequestMethod.DELETE, headersAuth);

            try
                response = request.send(URI(destination));
                if response.StatusCode ~= StatusCode.OK
                    warning("OpenaiBatch:DeleteHttpError", ...
                        "delete http error: %s\n%s", ...
                        string(response.StatusCode), ...
                        jsonencode(response.Body.Data));
                end
            catch ME
                warning("OpenaiBatch:DeleteFailed", ...
                    "Failed to delete file\n%s", ME.message);
            end
        end
    end
end