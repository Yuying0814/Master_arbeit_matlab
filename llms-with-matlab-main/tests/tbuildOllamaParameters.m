classdef tbuildOllamaParameters < matlab.unittest.TestCase
% Unit tests for llms.internal.buildOllamaParameters

%   Copyright 2025 The MathWorks, Inc.

    properties (Access = private)
        BasicMessages = {struct("role","user","content","Hello")};
        BasicFunctions = {struct("type","function","function",struct("name","test"))};
    end

    methods (Test)
        function basicParameters(testCase)
            messages = testCase.BasicMessages;
            
            nvp = testCase.createNVP(Temperature=0.7, TopP=0.9, MinP=0.1, TopK=40, ...
                TailFreeSamplingZ=0.95, StopSequences=["stop1","stop2"], MaxNumTokens=100);
            params = llms.internal.buildOllamaParameters("llama2", messages, {}, nvp);
            
            testCase.verifyEqual(params.model, "llama2");
            testCase.verifyEqual(params.messages, messages);
            testCase.verifyEqual(params.options.temperature, 0.7);
            testCase.verifyEqual(params.options.top_p, 0.9);
            testCase.verifyEqual(params.options.min_p, 0.1);
            testCase.verifyEqual(params.options.top_k, 40);
            testCase.verifyEqual(params.options.tfs_z, 0.95);
            testCase.verifyEqual(params.options.stop, ["stop1","stop2"]);
            testCase.verifyEqual(params.options.num_predict, 100);
        end

        function streamDisabled(testCase)
            nvp = testCase.createNVP(StreamFun=[]);
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyFalse(params.stream);
        end

        function streamEnabled(testCase)
            nvp = testCase.createNVP(StreamFun=@(x)disp(x));
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyTrue(params.stream);
        end

        function infValuesExcluded(testCase)
            nvp = testCase.createNVP(TopK=inf, MaxNumTokens=inf);
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyFalse(isfield(params.options, 'top_k'));
            testCase.verifyFalse(isfield(params.options, 'num_predict'));
        end

        function withTools(testCase)
            functions = testCase.BasicFunctions;
            nvp = testCase.createNVP();
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, functions, nvp);
            testCase.verifyEqual(params.tools, functions);
        end

        function withSeed(testCase)
            nvp = testCase.createNVP(Seed=42);
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.options.seed, 42);
        end

        function jsonResponseFormat(testCase)
            nvp = testCase.createNVP(ResponseFormat="json");
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyEqual(params.format, "json");
        end

        function structResponseFormat(testCase)
            prototype = struct("name","","age",0);
            nvp = testCase.createNVP(ResponseFormat=prototype);
            params = llms.internal.buildOllamaParameters("llama2", testCase.BasicMessages, {}, nvp);
            testCase.verifyTrue(isstruct(params.format));
            testCase.verifyEqual(params.format.type, "object");
        end
    end

    methods (Access = private)
        function nvp = createNVP(~, args)
            arguments
                ~
                args.Temperature = 1
                args.TopP = 1
                args.MinP = 0
                args.TopK = inf
                args.TailFreeSamplingZ = 1
                args.StopSequences = []
                args.MaxNumTokens = inf
                args.ResponseFormat = "text"
                args.Seed = []
                args.StreamFun = []
            end
            nvp = args;
        end
    end
end
