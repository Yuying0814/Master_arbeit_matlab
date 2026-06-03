classdef BatchJob < handle
    %BATCHJOB Summary of this class goes here
    %   Detailed explanation goes here
    properties(SetAccess = private)
        Name (1,1) string = ""
        InputPath (1,1) string = ""
        CustomIds (1,:) string = strings(1,0)
    end

    properties
        BatchId (1,1) string = ""
        InputFileId (1,1) string = ""
        OutputFileId (1,1) string = ""
        ErrorFileId (1,1) string = ""
        Status (1,1) string = "created"
        BatchInfo struct = struct()
    end
    
    methods
        function obj = BatchJob(name,customIds,inputPath)
            arguments
                name (1,1) string = ""
                customIds (1,:) string = strings(1,0)
                inputPath (1,1) string = ""
            end
            obj.Name = name;
            obj.InputPath = inputPath;
            obj.CustomIds = customIds;
        end
        
        function update(obj,opts)
            arguments
                obj (1,1) openai.BatchJob
                opts.BatchId (1,1) string
                opts.InputFileId (1,1) string
                opts.OutputFileId (1,1) string
                opts.ErrorFileId (1,1) string
                opts.Status (1,1) string
                opts.BatchInfo struct
            end

            if isfield(opts, "BatchId")
                obj.BatchId = opts.BatchId;
            end
        
            if isfield(opts, "InputFileId")
                obj.InputFileId = opts.InputFileId;
            end
        
            if isfield(opts, "OutputFileId")
                obj.OutputFileId = opts.OutputFileId;
            end
        
            if isfield(opts, "ErrorFileId")
                obj.ErrorFileId = opts.ErrorFileId;
            end
        
            if isfield(opts, "Status")
                obj.Status = opts.Status;
            end
        
            if isfield(opts, "BatchInfo")
                obj.updateBatchInfo(opts.BatchInfo);
            end
        end

        function updateBatchInfo(obj,batchInfo)
            arguments
                obj (1,1) openai.BatchJob
                batchInfo (1,1) struct
            end
        
            obj.BatchInfo = batchInfo;
                                        
            if isfield(batchInfo,"status")
                obj.update(Status=string(batchInfo.status));
            end
        
            if isfield(batchInfo,"output_file_id") && ~isempty(batchInfo.output_file_id)
                obj.update(OutputFileId=string(batchInfo.output_file_id));
            end
        
            if isfield(batchInfo,"error_file_id") && ~isempty(batchInfo.error_file_id)
                obj.update(ErrorFileId=string(batchInfo.error_file_id));
            end
        end

        function tf = isTerminal(obj)
            tf = any(obj.Status == ["completed", "failed", "cancelled", "expired"]);
        end

        function tf = isCompleted(obj)
            tf = obj.Status == "completed";
        end

        function tf = isFailed(obj)
            tf = any(obj.Status == ["failed", "cancelled", "expired"]);
        end

        function tf = isRunning(obj)
            tf = ~obj.isTerminal() && obj.Status ~= "created";
        end

        function tf = hasOutput(obj)
            tf = strlength(obj.OutputFileId) > 0;
        end

        function tf = hasErrorFile(obj)
            tf = strlength(obj.ErrorFileId) > 0;
        end
    end
end
